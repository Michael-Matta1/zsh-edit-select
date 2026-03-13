// Copyright (c) 2025 Michael Matta
// Version: 0.6.1
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
#include <io.h>
#include <fcntl.h>

/* Safety cap on clipboard reads. */
#define MAX_CLIPBOARD_SIZE (4 * 1024 * 1024)

/* Heartbeat interval in milliseconds (5 seconds). */
#define HEARTBEAT_MS 5000

/* Timer ID for periodic heartbeats / parent liveness checks. */
#define TIMER_ID_HEARTBEAT 1

/* The message-only window handle used by --daemon mode. */
static HWND g_hwnd = NULL;

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

    DWORD written = 0;
    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), buf, (DWORD)n, &written, NULL))
        return -1;
    return 0;
}

/* Write exactly `len` bytes to stdout.  Returns 0 on success. */
static int write_bytes(const char *data, size_t len) {
    HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
    size_t off = 0;
    while (off < len) {
        DWORD chunk = (DWORD)((len - off > 65536) ? 65536 : (len - off));
        DWORD written = 0;
        if (!WriteFile(hOut, data + off, chunk, &written, NULL))
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
/*  Entry point.                                                      */
/* ------------------------------------------------------------------ */
int main(int argc, char *argv[]) {
    int mode_daemon = 0;
    int mode_get_clipboard = 0;
    int mode_set_clipboard = 0;
    int mode_get_seq = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--daemon") == 0)
            mode_daemon = 1;
        else if (strcmp(argv[i], "--get-clipboard") == 0)
            mode_get_clipboard = 1;
        else if (strcmp(argv[i], "--set-clipboard") == 0)
            mode_set_clipboard = 1;
        else if (strcmp(argv[i], "--get-seq") == 0)
            mode_get_seq = 1;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "Usage: %s [--daemon|--get-clipboard|--set-clipboard|--get-seq]\n"
                "Windows clipboard helper for zsh-edit-select WSL backend.\n\n"
                "  --daemon          Monitor clipboard (event-driven, stdout protocol)\n"
                "  --get-clipboard   Print clipboard text to stdout\n"
                "  --set-clipboard   Read stdin, set as clipboard\n"
                "  --get-seq         Print clipboard sequence number\n",
                argv[0]);
            return 0;
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

    /* Default: daemon mode. */
    return run_daemon();
}
