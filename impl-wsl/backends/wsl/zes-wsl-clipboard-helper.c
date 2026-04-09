// Copyright (c) 2025 Michael Matta
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// Windows clipboard helper for zsh-edit-select WSL backend.
// Cross-compiled from WSL with MinGW:
//   x86_64-w64-mingw32-gcc -O2 -o zes-wsl-clipboard-helper.exe \
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
//   --wait-next-left-down Block until the next physical left-button press.
//   --handoff-scrollback Inject DOWN, wait for physical LEFT UP, inject UP.
//   --handoff-scrollback-vscode VS Code-safe handoff: avoids Win32 double-click.
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
/*  --wait-next-left-down: block until the next physical left click.  */
/*                                                                    */
/*  Waits for:  current UP (if held)  →  gap  →  next DOWN  →  UP.   */
/*                                                                    */
/*  Waiting for the full DOWN+UP instead of just DOWN ensures that    */
/*  the ZLE callback fires AFTER the user's next mouse interaction    */
/*  is fully complete, preventing two problems:                       */
/*  1. 1000h sent mid-drag: would switch VS Code back to tracking mode*/
/*     and interrupt the new drag the user intended.                  */
/*  2. Double-click selection auto-cleared: the re-arm callback used  */
/*     to fire while the user held the re-arm click, clearing the     */
/*     word selection before they could act on it.                    */
/*  By firing only after button-up, native interactions finish first. */
/* ------------------------------------------------------------------ */
static int run_wait_next_left_down(void) {
    #define NEXT_DOWN_TIMEOUT_MS 30000
    DWORD start = GetTickCount();

    /* If button is currently held (mid-interaction), wait for release. */
    while (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
        if (GetTickCount() - start >= NEXT_DOWN_TIMEOUT_MS) return 1;
        Sleep(5);
    }

    /* 150 ms gap: lets double-click word selections settle and remain
       visible long enough for the user to read / Ctrl+C before any
       accidental micro-movement triggers the next phase. */
    Sleep(150);

    /* Wait for the next press. */
    while (!(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
        if (GetTickCount() - start >= NEXT_DOWN_TIMEOUT_MS) return 1;
        Sleep(5);
    }

    /* Wait for the press to COMPLETE (button released) before signalling
       ZLE.  This prevents 1000h from being sent while the button is held,
       which would interrupt drags or clear visible selections. */
    while (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
        if (GetTickCount() - start >= NEXT_DOWN_TIMEOUT_MS) return 1;
        Sleep(5);
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
/*  --handoff-scrollback-vscode: VS Code-safe scrollback handoff.     */
/*                                                                    */
/*  No WH_MOUSE_LL hook: hooks require the installing thread to pump  */
/*  Win32 messages; sleeping without a message loop causes a system-  */
/*  wide mouse freeze.  GetAsyncKeyState at 1 ms is sufficient.       */
/*                                                                    */
/*  PATH 1 — DRAG: button held at entry, cursor moves > SM_CXDRAG.   */
/*    Inject DOWN immediately; drag duration exceeds dblclick window. */
/*    Wait for physical UP. Skip synthetic UP.                        */
/*                                                                    */
/*  PATH 2 — MULTI-CLICK: rising edge (UP→DOWN) detected within      */
/*    GetDoubleClickTime() after UP1.  Win32 generated WM_LBUTTONDBLCLK*/
/*    natively; VS Code already word/line selected.  Inject nothing.  */
/*                                                                    */
/*  PATH 3 — SINGLE CLICK: no second DOWN in the dblclick window.    */
/*    Inject DOWN+UP now — window has expired, no spurious dblclick.  */
/* ------------------------------------------------------------------ */
static int run_handoff_scrollback_vscode(void) {
    DWORD t_entry     = GetTickCount();
    DWORD dblclick_ms = GetDoubleClickTime();

    POINT p0;
    GetCursorPos(&p0);

    /* ---- PATH 1 probe: watch for drag while button is held ---- */
    if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
        for (;;) {
            POINT p1;
            GetCursorPos(&p1);
            int dx = p1.x - p0.x; if (dx < 0) dx = -dx;
            int dy = p1.y - p0.y; if (dy < 0) dy = -dy;
            /* Inject as soon as ANY cursor movement is detected.
               p0 is recorded at process-start (~65ms after physical DOWN),
               so the cursor has already moved past SM_CXDOUBLECLK relative
               to the original press — injecting at p0+1 px is therefore
               outside Win32's double-click zone and safe from dblclick.
               Using dx > 0 (not dx > SM_CXDRAG) removes the extra ~5 px
               threshold shift that caused "ello" to be selected instead of
               "hello".  The remaining ~13 px startup-delay shift is the
               unavoidable architectural minimum. */
            if (dx > 0 || dy > 0) {
                /* PATH 1 — DRAG */
                if (run_inject_left_down() != 0) return 1;
                run_wait_left_up();   /* poll-based wait, no hook needed */
                return 0;
            }
            if ((GetAsyncKeyState(VK_LBUTTON) & 0x8000) == 0)
                break;      /* UP1 detected */
            Sleep(1);       /* 1 ms: fine position sampling, no message pump needed */
        }
    }

    /* ---- PATH 2 probe: rising-edge detection for multi-click ---- */
    /* 1 ms polling catches UP1+DOWN2 transitions even if they occur   */
    /* within the same 5 ms window that coarser polling would miss.    */
    DWORD deadline  = t_entry + dblclick_ms + 10;
    BOOL  prev_down = FALSE;
    BOOL  multi     = FALSE;

    while (GetTickCount() < deadline) {
        BOOL cur_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;

        if (!prev_down && cur_down) {
            /* Rising edge: second (or third) physical press detected. */
            multi = TRUE;
            /* Drain second click UP. */
            while (GetAsyncKeyState(VK_LBUTTON) & 0x8000) Sleep(1);
            /* Drain optional triple-click within 150 ms (not a full
               dblclick_ms — that 500 ms wait delays Phase 2 start and
               shortens the visible selection window unnecessarily). */
            DWORD d3   = GetTickCount() + 150;
            BOOL  p3   = FALSE;
            while (GetTickCount() < d3) {
                BOOL c3 = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
                if (!p3 && c3)
                    while (GetAsyncKeyState(VK_LBUTTON) & 0x8000) Sleep(1);
                p3 = c3;
                Sleep(1);
            }
            break;
        }

        prev_down = cur_down;
        Sleep(1);
    }

    if (multi) {
        /* PATH 2 — MULTI-CLICK: native handling already applied. */
        return 0;
    }

    /* PATH 3 — SINGLE CLICK: dblclick window expired, safe to inject. */
    int rc = run_inject_left_down();
    if (rc != 0) return rc;
    return run_inject_left_up();
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
    int mode_wait_next_left_down = 0;
    int mode_handoff_scrollback = 0;
    int mode_handoff_scrollback_vscode = 0;

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
        else if (strcmp(argv[i], "--wait-next-left-down") == 0)
            mode_wait_next_left_down = 1;
        else if (strcmp(argv[i], "--handoff-scrollback") == 0)
            mode_handoff_scrollback = 1;
        else if (strcmp(argv[i], "--handoff-scrollback-vscode") == 0)
            mode_handoff_scrollback_vscode = 1;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "Usage: %s [--daemon|--get-clipboard|--set-clipboard|--get-seq|--inject-left-down|--inject-left-up|--wait-left-up|--wait-next-left-down|--handoff-scrollback]\n"
                "Windows clipboard helper for zsh-edit-select WSL backend.\n\n"
                "  --daemon          Monitor clipboard (event-driven, stdout protocol)\n"
                "  --get-clipboard   Print clipboard text to stdout\n"
                "  --set-clipboard   Read stdin, set as clipboard\n"
                "  --get-seq         Print clipboard sequence number\n"
                "  --inject-left-down Inject synthetic left-button down\n"
                "  --inject-left-up  Inject synthetic left-button up\n"
                "  --wait-left-up    Wait until physical left button is released\n"
                "  --wait-next-left-down Wait for next physical left-button press\n"
                "  --handoff-scrollback Atomic down/wait-physical-up/up gesture handoff\n"
                "  --handoff-scrollback-vscode VS Code-safe handoff (avoids dblclick)\n",
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
    if (mode_wait_next_left_down)
        return run_wait_next_left_down();
    if (mode_handoff_scrollback)
        return run_handoff_scrollback();
    if (mode_handoff_scrollback_vscode)
        return run_handoff_scrollback_vscode();

    /* Default (no args): daemon mode. */
    return run_daemon();
}
