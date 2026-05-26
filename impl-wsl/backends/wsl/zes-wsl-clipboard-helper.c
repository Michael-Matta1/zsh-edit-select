// Copyright (c) 2025 Michael Matta
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// Windows clipboard helper for zsh-edit-select WSL backend.
// Cross-compiled from WSL with MinGW:
//   x86_64-w64-mingw32-gcc -O2 -o zes-wsl-clipboard-helper.exe
//       zes-wsl-clipboard-helper.c -luser32
//
// Modes (first matching flag wins):
//   --daemon          Monitor clipboard changes via AddClipboardFormatListener,
//                     write events to stdout using a length-prefixed protocol.
//   --get-clipboard   Print clipboard text (UTF-8) to stdout and exit.
//   --set-clipboard   Read stdin (UTF-8), place on clipboard, and exit.
//   --get-seq         Print GetClipboardSequenceNumber() and exit.
//   --inject-left-down Inject synthetic left mouse button DOWN via SendInput.
//   --inject-left-up  Inject synthetic left mouse button UP via SendInput.
//   --wait-left-up    Block until physical left mouse button is released.
//   --handoff-scrollback Inject DOWN, wait for physical LEFT UP, inject UP.
//   --handoff-scrollback-vscode-shift VS Code xterm.js Shift-selection handoff.
//   --help / -h       Print usage to stderr and exit.

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <io.h>
#include <fcntl.h>

/* Safety cap on clipboard reads. */
#define MAX_CLIPBOARD_SIZE (4 * 1024 * 1024)

/* Heartbeat interval in milliseconds (5 seconds). */
#define HEARTBEAT_MS 5000

/* Maximum wait for physical left-button release during handoff. */
#define LEFT_UP_WAIT_TIMEOUT_MS 30000

/* Timer ID for periodic heartbeats / parent liveness checks. */
#define TIMER_ID_HEARTBEAT 1

/* The message-only window handle used by --daemon mode. */
static HWND g_hwnd = NULL;

/* Shared flag used by the low-level mouse hook wait path. */
static volatile LONG g_physical_left_up_seen = 0;

/* ------------------------------------------------------------------ */
/*  Clipboard read: CF_UNICODETEXT → UTF-8 malloc'd buffer.           */
/* ------------------------------------------------------------------ */
static char *read_clipboard_utf8(size_t *out_len) {
    *out_len = 0;

    if (!OpenClipboard(NULL))
        return NULL;

    HANDLE h = GetClipboardData(CF_UNICODETEXT);
    if (!h) {
        CloseClipboard();
        return NULL;
    }

    const wchar_t *wstr = (const wchar_t *)GlobalLock(h);
    if (!wstr) {
        CloseClipboard();
        return NULL;
    }

    int needed = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
    if (needed <= 0) {
        GlobalUnlock(h);
        CloseClipboard();
        return NULL;
    }

    char *buf = (char *)malloc((size_t)needed);
    if (!buf) {
        GlobalUnlock(h);
        CloseClipboard();
        return NULL;
    }

    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buf, needed, NULL, NULL);
    GlobalUnlock(h);
    CloseClipboard();

    /* needed includes the null terminator; the caller wants the byte count
       without the trailing NUL. */
    *out_len = (size_t)(needed - 1);
    return buf;
}

/* ------------------------------------------------------------------ */
/*  Clipboard write: UTF-8 buffer → CF_UNICODETEXT.                   */
/* ------------------------------------------------------------------ */
static int set_clipboard_utf8(const char *data, size_t len) {
    if (!data || len == 0)
        return 0;

    int wlen = MultiByteToWideChar(CP_UTF8, 0, data, (int)len, NULL, 0);
    if (wlen <= 0)
        return 0;

    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, (size_t)(wlen + 1) * sizeof(wchar_t));
    if (!hMem)
        return 0;

    wchar_t *wstr = (wchar_t *)GlobalLock(hMem);
    if (!wstr) {
        GlobalFree(hMem);
        return 0;
    }

    MultiByteToWideChar(CP_UTF8, 0, data, (int)len, wstr, wlen);
    wstr[wlen] = L'\0';
    GlobalUnlock(hMem);

    if (!OpenClipboard(NULL)) {
        GlobalFree(hMem);
        return 0;
    }

    EmptyClipboard();
    if (!SetClipboardData(CF_UNICODETEXT, hMem)) {
        GlobalFree(hMem);
        CloseClipboard();
        return 0;
    }

    /* After SetClipboardData succeeds, the system owns hMem — do not free it. */
    CloseClipboard();
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Read all of stdin into a malloc'd buffer.                         */
/* ------------------------------------------------------------------ */
static char *read_all_stdin(size_t *out_len) {
    /* Switch stdin to binary mode so CRLF is not translated. */
    _setmode(_fileno(stdin), _O_BINARY);

    size_t capacity = 4096, total = 0;
    char *buf = (char *)malloc(capacity);
    if (!buf) {
        *out_len = 0;
        return NULL;
    }

    while (total < MAX_CLIPBOARD_SIZE) {
        if (total + 4096 > capacity) {
            capacity *= 2;
            if (capacity > MAX_CLIPBOARD_SIZE)
                capacity = MAX_CLIPBOARD_SIZE;
            char *nb = (char *)realloc(buf, capacity);
            if (!nb) {
                free(buf);
                *out_len = 0;
                return NULL;
            }
            buf = nb;
        }
        DWORD n = 0;
        if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), buf + total, 4096, &n, NULL) || n == 0)
            break;
        total += n;
    }

    *out_len = total;
    return buf;
}

/* ------------------------------------------------------------------ */
/*  stdout helpers — binary mode, unbuffered.                         */
/* ------------------------------------------------------------------ */
static void init_stdout(void) {
    _setmode(_fileno(stdout), _O_BINARY);
    setvbuf(stdout, NULL, _IONBF, 0);
}

/* Write a line to stdout.  Returns 0 on success, -1 if the pipe broke. */
static int write_line(const char *fmt, ...) {
    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n <= 0)
        return -1;

    /* vsnprintf returns the full length that would have been written.
       Clamp to the local buffer to avoid out-of-bounds length usage. */
    if ((size_t)n >= sizeof(buf))
        n = (int)(sizeof(buf) - 1);

    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD off = 0;
    while (off < (DWORD)n) {
        DWORD written = 0;
        if (!WriteFile(hOut, buf + off, (DWORD)n - off, &written, NULL) || written == 0)
            return -1;
        off += written;
    }
    return 0;
}

/* Write exactly `len` bytes to stdout.  Returns 0 on success. */
static int write_bytes(const char *data, size_t len) {
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    size_t off = 0;
    while (off < len) {
        DWORD chunk = (DWORD)((len - off > 65536) ? 65536 : (len - off));
        DWORD written = 0;
        if (!WriteFile(hOut, data + off, chunk, &written, NULL) || written == 0)
            return -1;
        off += written;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/*  --daemon mode: event-driven clipboard monitoring.                 */
/*                                                                    */
/*  Creates a message-only window, registers AddClipboardFormatListener,*/
/*  and enters Win32 message loop.  WM_CLIPBOARDUPDATE fires when any */
/*  application modifies the clipboard.  The helper reads CF_UNICODETEXT*/
/*  and writes a length-prefixed message to stdout for the Linux-side  */
/*  agent to consume.                                                  */
/*                                                                    */
/*  Protocol (stdout):                                                */
/*    READY\n                     — helper initialised                */
/*    CLIPBOARD <seq> <len>\n     — clipboard changed (len bytes follow)*/
/*    <len bytes of UTF-8 text>   — raw content                       */
/*    EMPTY <seq>\n               — clipboard empty or non-text       */
/*    HEARTBEAT\n                 — periodic liveness signal           */
/* ------------------------------------------------------------------ */

static LRESULT CALLBACK ClipboardWndProc(HWND hwnd, UINT msg,
                                         WPARAM wParam, LPARAM lParam) {
    if (msg == WM_CLIPBOARDUPDATE) {
        DWORD seq = GetClipboardSequenceNumber();
        size_t len = 0;
        char *content = read_clipboard_utf8(&len);

        if (content && len > 0) {
            /* CLIPBOARD <seq> <len>\n<content> */
            if (write_line("CLIPBOARD %lu %zu\n", (unsigned long)seq, len) < 0) {
                PostQuitMessage(0);
                free(content);
                return 0;
            }
            if (write_bytes(content, len) < 0) {
                PostQuitMessage(0);
                free(content);
                return 0;
            }
        } else {
            /* EMPTY <seq>\n */
            if (write_line("EMPTY %lu\n", (unsigned long)seq) < 0) {
                PostQuitMessage(0);
                free(content);
                return 0;
            }
        }

        free(content);
        return 0;
    }

    if (msg == WM_TIMER && wParam == TIMER_ID_HEARTBEAT) {
        /* Periodic heartbeat: lets the Linux agent know we are alive,
           and detects a broken pipe (parent death) on write failure. */
        if (write_line("HEARTBEAT\n") < 0)
            PostQuitMessage(0);
        return 0;
    }

    if (msg == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }

    return DefWindowProcA(hwnd, msg, wParam, lParam);
}

static int run_daemon(void) {
    init_stdout();

    WNDCLASSA wc;
    memset(&wc, 0, sizeof(wc));
    wc.lpfnWndProc = ClipboardWndProc;
    wc.lpszClassName = "ZESWSLClipHelper";
    wc.hInstance = GetModuleHandle(NULL);

    if (!RegisterClassA(&wc)) {
        fprintf(stderr, "RegisterClass failed\n");
        return 1;
    }

    g_hwnd = CreateWindowExA(0, wc.lpszClassName, NULL,
                              0, 0, 0, 0, 0,
                              HWND_MESSAGE, NULL, wc.hInstance, NULL);
    if (!g_hwnd) {
        fprintf(stderr, "CreateWindow failed\n");
        return 1;
    }

    if (!AddClipboardFormatListener(g_hwnd)) {
        fprintf(stderr, "AddClipboardFormatListener failed\n");
        DestroyWindow(g_hwnd);
        return 1;
    }

    /* Start a periodic timer for heartbeats and parent-death detection. */
    SetTimer(g_hwnd, TIMER_ID_HEARTBEAT, HEARTBEAT_MS, NULL);

    /* Signal readiness to the Linux-side agent. */
    if (write_line("READY\n") < 0) {
        RemoveClipboardFormatListener(g_hwnd);
        DestroyWindow(g_hwnd);
        return 1;
    }

    /* Win32 message loop — truly event-driven, zero CPU while idle. */
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }

    KillTimer(g_hwnd, TIMER_ID_HEARTBEAT);
    RemoveClipboardFormatListener(g_hwnd);
    DestroyWindow(g_hwnd);
    return 0;
}

/* ------------------------------------------------------------------ */
/*  --get-clipboard: print current clipboard text to stdout.          */
/* ------------------------------------------------------------------ */
static int run_get_clipboard(void) {
    init_stdout();

    size_t len = 0;
    char *data = read_clipboard_utf8(&len);
    if (data && len > 0) {
        fwrite(data, 1, len, stdout);
        free(data);
        return 0;
    }
    free(data);
    return 1;
}

/* ------------------------------------------------------------------ */
/*  --set-clipboard: read stdin, place on clipboard.                  */
/* ------------------------------------------------------------------ */
static int run_set_clipboard(void) {
    size_t len = 0;
    char *data = read_all_stdin(&len);
    if (!data || len == 0) {
        free(data);
        return 1;
    }

    int ok = set_clipboard_utf8(data, len);
    free(data);
    return ok ? 0 : 1;
}

/* ------------------------------------------------------------------ */
/*  --get-seq: print GetClipboardSequenceNumber().                    */
/* ------------------------------------------------------------------ */
static int run_get_seq(void) {
    printf("%lu\n", (unsigned long)GetClipboardSequenceNumber());
    return 0;
}

/* ------------------------------------------------------------------ */
/*  --inject-left-down: inject synthetic left-button DOWN event.      */
/* ------------------------------------------------------------------ */
static int run_inject_left_down(void) {
    INPUT in;
    memset(&in, 0, sizeof(in));
    in.type = INPUT_MOUSE;
    in.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

    UINT sent = SendInput(1, &in, sizeof(INPUT));
    return (sent == 1) ? 0 : 1;
}

/* ------------------------------------------------------------------ */
/*  --inject-left-up: inject synthetic left-button UP event.          */
/* ------------------------------------------------------------------ */
static int run_inject_left_up(void) {
    INPUT in;
    memset(&in, 0, sizeof(in));
    in.type = INPUT_MOUSE;
    in.mi.dwFlags = MOUSEEVENTF_LEFTUP;

    UINT sent = SendInput(1, &in, sizeof(INPUT));
    return (sent == 1) ? 0 : 1;
}

/* VS Code drag recovery uses UP->DOWN to leave xterm.js's already-consumed
   tracking gesture and begin a fresh native Shift-selection drag. */
static int run_inject_left_up_down(void) {
    INPUT in[2];
    memset(in, 0, sizeof(in));

    in[0].type = INPUT_MOUSE;
    in[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;

    in[1].type = INPUT_MOUSE;
    in[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

    UINT sent = SendInput(2, in, sizeof(INPUT));
    return (sent == 2) ? 0 : 1;
}

static LONG normalize_absolute_coord(int value, int origin, int span) {
    if (span <= 1)
        return 0;
    return (LONG)(((value - origin) * 65535LL) / (span - 1));
}

static int fill_absolute_move(INPUT *in, POINT pt) {
    int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
    int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
    int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (vw <= 0 || vh <= 0)
        return 1;

    memset(in, 0, sizeof(*in));
    in->type = INPUT_MOUSE;
    in->mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK;
    in->mi.dx = normalize_absolute_coord(pt.x, vx, vw);
    in->mi.dy = normalize_absolute_coord(pt.y, vy, vh);
    return 0;
}

/* VS Code drag startup can lag behind the physical press. Replaying the
   synthetic DOWN at the helper's first observed point preserves the earliest
   anchor available without a global hook or a resident recorder. */
static int run_inject_left_up_down_at_anchor(POINT anchor, POINT current) {
    INPUT in[4];
    memset(in, 0, sizeof(in));

    in[0].type = INPUT_MOUSE;
    in[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;

    if (fill_absolute_move(&in[1], anchor) != 0)
        return run_inject_left_up_down();

    in[2].type = INPUT_MOUSE;
    in[2].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

    if (fill_absolute_move(&in[3], current) != 0)
        return run_inject_left_up_down();

    UINT sent = SendInput(4, in, sizeof(INPUT));
    if (sent != 4) {
        (void)run_inject_left_up();
        return 1;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Synthetic Shift key helpers for VS Code's xterm.js path only.      */
/*                                                                    */
/*  xterm.js deliberately lets Shift+mouse use native terminal         */
/*  selection even while DECSET mouse tracking is enabled. The shell   */
/*  uses these helpers only for the VS Code handoff mode so Windows    */
/*  Terminal keeps using its existing mouse-event replay path.          */
/* ------------------------------------------------------------------ */
static int run_shift_key(BOOL down) {
    INPUT in;
    memset(&in, 0, sizeof(in));
    in.type = INPUT_KEYBOARD;
    in.ki.wVk = VK_SHIFT;
    if (!down)
        in.ki.dwFlags = KEYEVENTF_KEYUP;

    UINT sent = SendInput(1, &in, sizeof(INPUT));
    return (sent == 1) ? 0 : 1;
}

static int run_shift_down(void) {
    return run_shift_key(TRUE);
}

static int run_shift_up(void) {
    return run_shift_key(FALSE);
}

static BOOL key_is_down(int vk) {
    return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

static int abs_int(int v) {
    return (v < 0) ? -v : v;
}

static int max_int(int a, int b) {
    return (a > b) ? a : b;
}

/* ------------------------------------------------------------------ */
/*  --wait-left-up: block until physical left button is released.     */
/* ------------------------------------------------------------------ */
static int run_wait_left_up(void) {
    DWORD start = GetTickCount();
    while (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
        DWORD elapsed = GetTickCount() - start;
        if (elapsed >= LEFT_UP_WAIT_TIMEOUT_MS)
            return 1;  /* Timed out — avoid infinite spin. */
        Sleep(1);
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/*  --handoff-scrollback: atomic down/wait/up handoff.                */
/*                                                                    */
/*  Uses a low-level mouse hook to wait for a real (non-injected)     */
/*  left-button release event, avoiding races and sticky synthetic     */
/*  hold states that can occur when polling only GetAsyncKeyState.     */
/* ------------------------------------------------------------------ */
static LRESULT CALLBACK WaitPhysicalLeftUpHookProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode == HC_ACTION && wParam == WM_LBUTTONUP) {
        const MSLLHOOKSTRUCT *info = (const MSLLHOOKSTRUCT *)lParam;
        if (info && ((info->flags & LLMHF_INJECTED) == 0)) {
            InterlockedExchange(&g_physical_left_up_seen, 1);
        }
    }
    return CallNextHookEx(NULL, nCode, wParam, lParam);
}

static int wait_for_physical_left_up_with_hook(DWORD timeout_ms) {
    DWORD start = GetTickCount();
    MSG msg;

    for (;;) {
        if (InterlockedCompareExchange(&g_physical_left_up_seen, 0, 0)) {
            return 0;
        }

        if (timeout_ms > 0) {
            DWORD elapsed = GetTickCount() - start;
            if (elapsed >= timeout_ms) {
                return 1;
            }
        }

        DWORD wait_ms = 50;
        if (timeout_ms > 0) {
            DWORD elapsed = GetTickCount() - start;
            DWORD remain = (elapsed >= timeout_ms) ? 0 : (timeout_ms - elapsed);
            if (remain < wait_ms) {
                wait_ms = remain;
            }
        }

        DWORD wait_result = MsgWaitForMultipleObjects(0, NULL, FALSE, wait_ms, QS_ALLINPUT);
        if (wait_result == WAIT_FAILED) {
            return 1;
        }
        if (wait_result == WAIT_OBJECT_0) {
            while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE)) {
                TranslateMessage(&msg);
                DispatchMessageA(&msg);
            }
        }

        /* Fail-safe: if no button is currently down, consider the gesture ended. */
        if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0) {
            return 0;
        }
    }
}

static int run_handoff_scrollback(void) {
    HHOOK hook = NULL;
    int rc = 0;
    int rc_down = 0;
    int rc_up = 0;

    InterlockedExchange(&g_physical_left_up_seen, 0);

    hook = SetWindowsHookExA(WH_MOUSE_LL, WaitPhysicalLeftUpHookProc, GetModuleHandle(NULL), 0);
    if (!hook) {
        /* Fallback for restricted environments: preserve prior behavior. */
        if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0) {
            rc_down = run_inject_left_down();
            rc_up = run_inject_left_up();
            return (rc_down == 0 && rc_up == 0) ? 0 : 1;
        }
        if (run_inject_left_down() != 0) {
            return 1;
        }
        run_wait_left_up();
        return run_inject_left_up();
    }

    if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0) {
        rc_down = run_inject_left_down();
        rc_up = run_inject_left_up();
        rc = (rc_down == 0 && rc_up == 0) ? 0 : 1;
        UnhookWindowsHookEx(hook);
        return rc;
    }

    if (run_inject_left_down() != 0) {
        UnhookWindowsHookEx(hook);
        return 1;
    }

    /* Timeout is fail-safe only; we still always send UP to avoid sticky hold. */
    (void)wait_for_physical_left_up_with_hook(LEFT_UP_WAIT_TIMEOUT_MS);
    rc = run_inject_left_up();

    UnhookWindowsHookEx(hook);
    return rc;
}

/* ------------------------------------------------------------------ */
/*  --handoff-scrollback-vscode-shift: VS Code native-selection path.  */
/*                                                                    */
/*  VS Code's xterm.js clears visible selection when mouse tracking is */
/*  re-enabled. Rather than toggling DECSET 1000/1002/1006 off and on, */
/*  this mode keeps tracking armed and temporarily holds Shift, which  */
/*  is xterm.js's built-in "force native selection" override.          */
/*                                                                    */
/*  The first physical click has already been consumed by mouse        */
/*  tracking before the shell calls this helper. Replaying a tap would */
/*  add one to Chromium's click count, so taps are never replayed. For */
/*  drags, a synthetic UP resets xterm.js's tracked button state before */
/*  a synthetic Shift+DOWN starts a native browser selection. For      */
/*  double/triple-clicks, Shift is held across the native follow-up    */
/*  clicks, matching the user's manual Shift-selection workaround.      */
/* ------------------------------------------------------------------ */
static int run_handoff_scrollback_vscode_shift(void) {
    DWORD start = GetTickCount();
    DWORD dblclick_ms = GetDoubleClickTime();
    if (dblclick_ms < 100) dblclick_ms = 100;
    if (dblclick_ms > 1000) dblclick_ms = 1000;

    POINT origin;
    GetCursorPos(&origin);

    BOOL shift_was_down = key_is_down(VK_SHIFT);
    BOOL sent_shift = FALSE;
    BOOL synthetic_down = FALSE;
    int rc = 0;
    int drag_tolerance_x = max_int(GetSystemMetrics(SM_CXDRAG), 2);
    int drag_tolerance_y = max_int(GetSystemMetrics(SM_CYDRAG), 2);

    if (!shift_was_down) {
        if (run_shift_down() != 0)
            return 1;
        sent_shift = TRUE;
    }

    /* Drag handoff: movement is the proof that this is not a stationary tap.
       VS Code/xterm.js already handled the physical DOWN as a tracking event,
       so an UP->DOWN pair under Shift gives native selection a fresh start
       without adding an extra click to simple single/double/triple clicks. */
    if (key_is_down(VK_LBUTTON)) {
        while (key_is_down(VK_LBUTTON)) {
            POINT cur;
            GetCursorPos(&cur);
            int dx = abs_int(cur.x - origin.x);
            int dy = abs_int(cur.y - origin.y);

            if (!synthetic_down && (dx > drag_tolerance_x || dy > drag_tolerance_y)) {
                /* VS Code drag startup is latency-sensitive. Installing a
                   WH_MOUSE_LL hook at this point can briefly stall Chromium's
                   mouse pipeline; polling the physical release preserves the
                   same UP->DOWN->UP handoff without entering that hook path. */
                if (run_inject_left_up_down_at_anchor(origin, cur) != 0) {
                    rc = 1;
                    goto done;
                }
                synthetic_down = TRUE;
            }

            if (GetTickCount() - start >= LEFT_UP_WAIT_TIMEOUT_MS) {
                rc = 1;
                goto done;
            }
            Sleep(1);
        }

        if (synthetic_down) {
            if (run_inject_left_up() != 0 && rc == 0)
                rc = 1;
            goto done;
        }
    }

    /* Multi-click handoff: keep Shift pressed until the double-click window
       goes quiet. Each real follow-up click extends the window, so triple
       click can still promote word selection to line selection. */
    DWORD deadline = GetTickCount() + dblclick_ms + 20;
    DWORD hard_deadline = start + (2 * dblclick_ms) + 250;
    BOOL was_down = key_is_down(VK_LBUTTON);
    while (GetTickCount() < deadline && GetTickCount() < hard_deadline) {
        BOOL down = key_is_down(VK_LBUTTON);
        if (down && !was_down) {
            while (key_is_down(VK_LBUTTON)) {
                if (GetTickCount() >= hard_deadline)
                    break;
                Sleep(1);
            }
            deadline = GetTickCount() + dblclick_ms + 20;
        }
        was_down = down;
        Sleep(1);
    }

done:
    if (sent_shift)
        run_shift_up();
    return rc;
}

/* ------------------------------------------------------------------ */
/*  Entry point.                                                      */
/* ------------------------------------------------------------------ */
int main(int argc, char *argv[]) {
    int mode_daemon = 0;
    int mode_get_clipboard = 0;
    int mode_set_clipboard = 0;
    int mode_get_seq = 0;
    int mode_inject_left_down = 0;
    int mode_inject_left_up = 0;
    int mode_wait_left_up = 0;
    int mode_handoff_scrollback = 0;
    int mode_handoff_scrollback_vscode_shift = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--daemon") == 0)
            mode_daemon = 1;
        else if (strcmp(argv[i], "--get-clipboard") == 0)
            mode_get_clipboard = 1;
        else if (strcmp(argv[i], "--set-clipboard") == 0)
            mode_set_clipboard = 1;
        else if (strcmp(argv[i], "--get-seq") == 0)
            mode_get_seq = 1;
        else if (strcmp(argv[i], "--inject-left-down") == 0)
            mode_inject_left_down = 1;
        else if (strcmp(argv[i], "--inject-left-up") == 0)
            mode_inject_left_up = 1;
        else if (strcmp(argv[i], "--wait-left-up") == 0)
            mode_wait_left_up = 1;
        else if (strcmp(argv[i], "--handoff-scrollback") == 0)
            mode_handoff_scrollback = 1;
        else if (strcmp(argv[i], "--handoff-scrollback-vscode-shift") == 0)
            mode_handoff_scrollback_vscode_shift = 1;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "Usage: %s [--daemon|--get-clipboard|--set-clipboard|--get-seq|--inject-left-down|--inject-left-up|--wait-left-up|--handoff-scrollback|--handoff-scrollback-vscode-shift]\n"
                "Windows clipboard helper for zsh-edit-select WSL backend.\n\n"
                "  --daemon          Monitor clipboard (event-driven, stdout protocol)\n"
                "  --get-clipboard   Print clipboard text to stdout\n"
                "  --set-clipboard   Read stdin, set as clipboard\n"
                "  --get-seq         Print clipboard sequence number\n"
                "  --inject-left-down Inject synthetic left-button down\n"
                "  --inject-left-up  Inject synthetic left-button up\n"
                "  --wait-left-up    Wait until physical left button is released\n"
                "  --handoff-scrollback Atomic down/wait-physical-up/up gesture handoff\n"
                "  --handoff-scrollback-vscode-shift VS Code Shift-selection handoff\n",
                argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            return 1;
        }
    }

    if (mode_daemon)
        return run_daemon();
    if (mode_get_clipboard)
        return run_get_clipboard();
    if (mode_set_clipboard)
        return run_set_clipboard();
    if (mode_get_seq)
        return run_get_seq();
    if (mode_inject_left_down)
        return run_inject_left_down();
    if (mode_inject_left_up)
        return run_inject_left_up();
    if (mode_wait_left_up)
        return run_wait_left_up();
    if (mode_handoff_scrollback)
        return run_handoff_scrollback();
    if (mode_handoff_scrollback_vscode_shift)
        return run_handoff_scrollback_vscode_shift();

    /* Default (no args): daemon mode. */
    return run_daemon();
}
