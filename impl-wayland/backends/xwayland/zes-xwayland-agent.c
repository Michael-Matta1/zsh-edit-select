// Copyright (c) 2025 Michael Matta
// Version: 0.5.7
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// XWayland clipboard integration agent for zsh-edit-select.
// Uses X11 XFixes through XWayland — completely invisible on Wayland
// compositors. Supports clipboard operations and PRIMARY clearing.
// Compile: gcc -O3 zes-xwayland-agent.c -o zes-xwayland-agent -lX11 -lXfixes

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <time.h>
#include <stdbool.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xfixes.h>

/* Cache-directory filenames and safety cap.
   PRIMARY_FILE / SEQ_FILE: selected text and change counter.
   PID_FILE: daemon PID for liveness checks.
   MAX_SELECTION_SIZE: 1 MB cap on selection reads. */
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "agent.pid"
#define MAX_SELECTION_SIZE (1024 * 1024)

static volatile sig_atomic_t running = 1;
static char cache_dir[512];
static char primary_path[560];
static char seq_path[560];
static char pid_path[560];

/* X11/XWayland connection state and interned selection atoms. */
/* X11/XWayland connection handle and root window. */
static Display *dpy = NULL;
static Window root;
/* Standard X11 selection and conversion atoms.
   XWayland runs an isolated per-session X server, so using xa_primary
   and xa_clipboard directly as conversion property names is safe:
   there is no risk of clashing with properties written by unrelated X clients. */
static Atom xa_primary;
static Atom xa_clipboard;
static Atom xa_utf8_string;
static Atom xa_targets;
/* Monotonically increasing counter written to SEQ_FILE; the shell polls
   its mtime to detect selection changes without reading content. */
static unsigned long seq_counter = 0;

/* Persistent fds for write_primary() daemon hot path.
   Opened once after daemon() in run_daemon(); reused for all subsequent writes.
   -1 = not yet open (pre-daemon initial write uses the open/write/close fallback). */
static int fd_primary = -1;
static int fd_seq     = -1;

/* SIGTERM / SIGINT handler — sets the flag that exits the event loop. */
static void signal_handler(int sig) {
    (void)sig;
    running = 0;
}

/* Resolve cache directory path (argument > XDG_RUNTIME_DIR > /dev/shm > HOME),
   populate path globals, and create the directory.  Returns 0 on success. */
static int ensure_cache_dir(const char *dir) {
    if (dir && dir[0]) {
        snprintf(cache_dir, sizeof(cache_dir), "%s", dir);
    } else {
        /* Cache location priority:
           1. XDG_RUNTIME_DIR/<uid> — tmpfs, cleaned by PAM on logout.
           2. /dev/shm — in-memory tmpfs on Linux; fast for short-lived modes.
           3. HOME/.cache — persistent fallback for non-standard environments. */
        const char *runtime = getenv("XDG_RUNTIME_DIR");
        if (runtime) {
            snprintf(cache_dir, sizeof(cache_dir), "%s/zsh-edit-select-%d",
                     runtime, (int)getuid());
        } else if (access("/dev/shm", W_OK | X_OK) == 0) {
            snprintf(cache_dir, sizeof(cache_dir),
                     "/dev/shm/zsh-edit-select-%d", (int)getuid());
        } else {
            const char *home = getenv("HOME");
            if (!home) return -1;
            snprintf(cache_dir, sizeof(cache_dir),
                     "%s/.cache/zsh-edit-select", home);
        }
    }
    snprintf(primary_path, sizeof(primary_path), "%s/%s", cache_dir, PRIMARY_FILE);
    snprintf(seq_path, sizeof(seq_path), "%s/%s", cache_dir, SEQ_FILE);
    snprintf(pid_path, sizeof(pid_path), "%s/%s", cache_dir, PID_FILE);

    struct stat st;
    if (stat(cache_dir, &st) == -1) {
        if (mkdir(cache_dir, 0700) == -1 && errno != EEXIST)
            return -1;
    }
    return 0;
}

/* Write selection text to PRIMARY cache and the sequence number to SEQ.
   Uses persistent fds in daemon mode, open/write/close otherwise. */
static void write_primary(const char *data, size_t len, unsigned long seq) {
    if (fd_primary >= 0) {
        /* Persistent-fd hot path: seek to start, write new content, then
           truncate to correct length.  ftruncate is mandatory — without it,
           content that shrinks between events (e.g. "hello world" → "hi")
           leaves stale bytes at the end that the shell reads as part of the
           new selection.  The (void) casts match the existing style. */
        if (len > 0 && data) {
            ssize_t r = pwrite(fd_primary, data, len, 0);
            (void)r;
        }
        (void)ftruncate(fd_primary, (off_t)len);

        /* primary must be fully committed before seq is touched —
           seq's mtime is the shell's only per-keypress detection signal. */
        char buf[24];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = pwrite(fd_seq, buf, (size_t)n, 0);
        (void)r;
        (void)ftruncate(fd_seq, (off_t)n);
        return;
    }

    /* Fallback path: used for the pre-daemon() initial write (fd_primary is
       still -1 at that point) and if open() failed after daemon().
       All short-lived modes (--oneshot, --get-clipboard, --copy-clipboard,
       --clear-primary) also use this path since they never open persistent fds. */
    int fd = open(primary_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) return;
    if (len > 0 && data) {
        ssize_t r = write(fd, data, len);
        (void)r;
    }
    close(fd);

    fd = open(seq_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd >= 0) {
        char buf[24];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = write(fd, buf, n);
        (void)r;
        close(fd);
    }
}

/* Request PRIMARY selection text from the XWayland X11 server.
 * Uses xa_primary directly as the conversion property, which is safe
 * because XWayland has an isolated per-session X server with no risk
 * of clashing with properties written by unrelated clients.
 *
 * Returns a malloc'd buffer (caller must free) or NULL on failure/timeout. */
static char *get_primary_selection(size_t *out_len) {
    Window owner = XGetSelectionOwner(dpy, xa_primary);
    if (owner == None) {
        *out_len = 0;
        return NULL;
    }

    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XConvertSelection(dpy, xa_primary, xa_utf8_string, xa_primary, w, CurrentTime);
    XFlush(dpy);
    XEvent ev;
    bool got_notify = false;
    {
        int xfd = XConnectionNumber(dpy);
        struct pollfd pfd = { .fd = xfd, .events = POLLIN };
        int elapsed_ms = 0;
        while (elapsed_ms < 500) {
            if (XCheckTypedWindowEvent(dpy, w, SelectionNotify, &ev)) {
                got_notify = true;
                break;
            }
            /* Short initial polls catch the common 1-5 ms roundtrip without
               overshooting; longer polls after 20 ms reduce syscall rate. */
            int wait = (elapsed_ms < 20) ? 5 : 20;
            int ret = poll(&pfd, 1, wait);
            if (ret < 0 && errno != EINTR) break;
            elapsed_ms += wait;
        }
    }

    char *data = NULL;
    *out_len = 0;

    if (got_notify && ev.xselection.property != None) {
        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *prop = NULL;

        if (XGetWindowProperty(dpy, w, xa_primary, 0, MAX_SELECTION_SIZE / 4,
                               False, AnyPropertyType, &actual_type, &actual_format,
                               &nitems, &bytes_after, &prop) == Success) {
            if (prop && nitems > 0) {
                *out_len = nitems;
                data = malloc(nitems);
                if (data) memcpy(data, prop, nitems);
            }
            if (prop) XFree(prop);
        }
    }

    XDestroyWindow(dpy, w);
    return data;
}

/* Re-read the current PRIMARY selection from the X server and
   unconditionally update cache, incrementing the sequence counter.
   Called on every XFixes owner-change notification. */
static void check_and_update_primary(void) {
    size_t len = 0;
    char *sel = get_primary_selection(&len);

    /* Always increment seq even when content is identical — a reselect
       of exactly the same text must still fire a new event in the shell. */
    seq_counter++;
    write_primary(sel ? sel : "", sel ? len : 0, seq_counter);
    free(sel);
}

/* Print current PRIMARY selection to stdout and exit.
 * Used when the daemon is not running and the shell needs a one-shot read. */
static int run_oneshot(void) {
    size_t len = 0;
    char *data = get_primary_selection(&len);
    if (data && len > 0) {
        fwrite(data, 1, len, stdout);
        free(data);
        return 0;
    }
    free(data);
    return 1;
}

/* Read the specified X11 selection (PRIMARY or CLIPBOARD) into a malloc'd buffer.
 * Uses xa_primary or xa_clipboard directly as the property atom for the
 * conversion reply (safe in XWayland's isolated X server). */
static char *get_selection(Atom selection, size_t *out_len) {
    Window owner = XGetSelectionOwner(dpy, selection);
    if (owner == None) {
        *out_len = 0;
        return NULL;
    }

    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    Atom prop_atom = (selection == xa_primary) ? xa_primary : xa_clipboard;
    XConvertSelection(dpy, selection, xa_utf8_string, prop_atom, w, CurrentTime);
    XFlush(dpy);

    XEvent ev;
    bool got_notify = false;
    {
        int xfd = XConnectionNumber(dpy);
        struct pollfd pfd = { .fd = xfd, .events = POLLIN };
        int elapsed_ms = 0;
        while (elapsed_ms < 500) {
            if (XCheckTypedWindowEvent(dpy, w, SelectionNotify, &ev)) {
                got_notify = true;
                break;
            }
            /* Short initial polls catch the common 1-5 ms roundtrip without
               overshooting; longer polls after 20 ms reduce syscall rate. */
            int wait = (elapsed_ms < 20) ? 5 : 20;
            int ret = poll(&pfd, 1, wait);
            if (ret < 0 && errno != EINTR) break;
            elapsed_ms += wait;
        }
    }

    char *data = NULL;
    *out_len = 0;

    if (got_notify && ev.xselection.property != None) {
        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *prop = NULL;

        if (XGetWindowProperty(dpy, w, prop_atom, 0, MAX_SELECTION_SIZE / 4,
                               False, AnyPropertyType, &actual_type, &actual_format,
                               &nitems, &bytes_after, &prop) == Success) {
            if (prop && nitems > 0) {
                *out_len = nitems;
                data = malloc(nitems);
                if (data) memcpy(data, prop, nitems);
            }
            if (prop) XFree(prop);
        }
    }

    XDestroyWindow(dpy, w);
    return data;
}

/* Print clipboard (CLIPBOARD selection) text to stdout and exit. */
static int run_get_clipboard(void) {
    size_t len = 0;
    char *data = get_selection(xa_clipboard, &len);
    if (data && len > 0) {
        fwrite(data, 1, len, stdout);
        free(data);
        return 0;
    }
    free(data);
    return 1;
}

/* Read all of stdin into a malloc'd buffer.  Used by --copy-clipboard
 * to capture the content before the agent takes clipboard ownership. */
static char *read_all_stdin(size_t *out_len) {
    size_t capacity = 4096, total = 0;
    char *buf = malloc(capacity);
    if (!buf) return NULL;

    while (1) {
        if (total + 4096 > capacity) {
            capacity *= 2;
            if (capacity > MAX_SELECTION_SIZE) break;
            char *nb = realloc(buf, capacity);
            if (!nb) { free(buf); *out_len = 0; return NULL; }
            buf = nb;
        }
        ssize_t n = read(STDIN_FILENO, buf + total, 4096);
        if (n > 0) total += n;
        else break;
    }
    *out_len = total;
    return buf;
}

/* A selection_request_received flag prevents the 50-second idle
   timeout from expiring while the agent is actively serving pastes. */
static bool selection_request_received = false;

/* Respond to a SelectionRequest event.
 * TARGETS: advertise supported formats so requestors can negotiate.
 * UTF8_STRING / XA_STRING: write text into the requestor's property and
 *   set selection_request_received to prevent idle timeout. */
static int handle_selection_request(XSelectionRequestEvent *req,
                                     const char *data, size_t data_len) {
    XEvent response;
    memset(&response, 0, sizeof(response));
    response.xselection.type = SelectionNotify;
    response.xselection.requestor = req->requestor;
    response.xselection.selection = req->selection;
    response.xselection.target = req->target;
    response.xselection.time = req->time;
    response.xselection.property = None;

    if (req->target == xa_targets) {
        Atom targets[] = { xa_targets, xa_utf8_string, XA_STRING };
        XChangeProperty(dpy, req->requestor, req->property,
                        XA_ATOM, 32, PropModeReplace,
                        (unsigned char *)targets, 3);
        response.xselection.property = req->property;
    } else if (req->target == xa_utf8_string || req->target == XA_STRING) {
        XChangeProperty(dpy, req->requestor, req->property,
                        req->target, 8, PropModeReplace,
                        (unsigned char *)data, data_len);
        response.xselection.property = req->property;
        selection_request_received = true;
    }

    XSendEvent(dpy, req->requestor, False, 0, &response);
    XFlush(dpy);
    return 0;
}

/* Set stdin as the clipboard and serve paste requests from the background.
 * Forks a background child that loops serving SelectionRequest events;
 * the parent exits immediately so the shell is not blocked. */
static int run_copy_clipboard(void) {
    size_t data_len = 0;
    char *data = read_all_stdin(&data_len);
    if (!data || data_len == 0) {
        free(data);
        return 1;
    }

    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XSetSelectionOwner(dpy, xa_clipboard, w, CurrentTime);

    if (XGetSelectionOwner(dpy, xa_clipboard) != w) {
        free(data);
        XDestroyWindow(dpy, w);
        return 1;
    }

    XFlush(dpy);

    /* Fork a background process to serve paste requests */
    pid_t pid = fork();
    if (pid < 0) {
        free(data);
        XDestroyWindow(dpy, w);
        return 1;
    }
    if (pid > 0) {
        _exit(0);
    }

    /* Child: background clipboard server.
       setsid() creates a new session so the child is not killed when the
       parent shell exits.  SIGHUP is ignored because the terminal hangup
       signal would otherwise terminate it when the user closes the window. */
    setsid();
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, SIG_IGN);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    int timeout_count = 0;
    /* Each poll sleeps 100 ms; 500 iterations = 50 s.  The timeout resets
       after every served request so an active clipboard session never expires. */
    while (running && timeout_count < 500) {  /* 50 second timeout */
        while (XPending(dpy) > 0) {
            XEvent ev;
            XNextEvent(dpy, &ev);

            if (ev.type == SelectionRequest) {
                handle_selection_request(&ev.xselectionrequest, data, data_len);
            } else if (ev.type == SelectionClear) {
                running = 0;
                break;
            }
        }

        if (!running) break;

        {
            struct pollfd pfd = { .fd = XConnectionNumber(dpy), .events = POLLIN };
            int ret = poll(&pfd, 1, 100);
            if (ret < 0 && errno != EINTR) break;
        }
        if (selection_request_received) {
            timeout_count = 0;  /* Reset timeout after serving a request */
            selection_request_received = false;
        } else {
            timeout_count++;
        }
    }

    free(data);
    XDestroyWindow(dpy, w);
    _exit(0);
}

/* Clear PRIMARY by setting its owner to None.
 * X11 interprets None owner as "no selection"; subsequent XGetSelectionOwner
 * calls from other clients will return None, indicating no text is selected. */
static int run_clear_primary(void) {
    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XSetSelectionOwner(dpy, xa_primary, None, CurrentTime);
    XFlush(dpy);
    XDestroyWindow(dpy, w);
    return 0;
}

/* Daemon mode: set up cache, daemonise, subscribe to XFixes PRIMARY
   owner-change events, and enter the poll-based event loop writing
   selection changes to cache until SIGTERM. */
static int run_daemon(const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "Cannot create cache directory\n");
        return 1;
    }

    /* Write empty cache files before daemonising so the shell never reads
       a missing file in the window between agent launch and first write.
       seq is seeded from time(NULL) for monotonic ordering across restarts. */
    seq_counter = (unsigned long)time(NULL);
    write_primary("", 0, seq_counter);

    if (daemon(0, 0) != 0) {
        perror("daemon");
        return 1;
    }

    FILE *f = fopen(pid_path, "w");
    if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);

    /* Open persistent fds for write_primary() hot path */
    fd_primary = open(primary_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
    fd_seq     = open(seq_path,    O_WRONLY | O_CREAT | O_CLOEXEC, 0644);

    /* XFixes is required for owner-change notifications.  Failure here
       typically means XWayland is not running, in which case the Wayland
       native agent should be used instead. */
    int xfixes_event_base, xfixes_error_base;
    if (!XFixesQueryExtension(dpy, &xfixes_event_base, &xfixes_error_base)) {
        fprintf(stderr, "XFixes extension not available (XWayland not running?)\n");
        if (fd_primary >= 0) { close(fd_primary); fd_primary = -1; }
        if (fd_seq     >= 0) { close(fd_seq);     fd_seq     = -1; }
        return 1;
    }

    /* Subscribe to PRIMARY owner-change events only; content-change polling
       is handled by calling check_and_update_primary on each notification. */
    XFixesSelectSelectionInput(dpy, root, xa_primary,
                                XFixesSetSelectionOwnerNotifyMask);
    XFlush(dpy);

    /* Populate the cache immediately with any pre-existing selection. */
    check_and_update_primary();

    /* poll()-based event loop: XNextEvent() blocks indefinitely and with
       glibc's signal() (SA_RESTART), SIGTERM cannot interrupt it.  Using
       poll() with a 1-second timeout ensures clean shutdown within 1s.
       XPending() drains Xlib's internal buffer before we call poll() again
       — data may have arrived during a previous read() that filled Xlib's
       buffer with multiple events. */
    {
        int xfd = XConnectionNumber(dpy);
        while (running) {
            struct pollfd pfd = { .fd = xfd, .events = POLLIN };
            int ret = poll(&pfd, 1, 1000);
            if (ret < 0 && errno != EINTR) break;
            while (XPending(dpy) > 0) {
                XEvent ev;
                XNextEvent(dpy, &ev);
                if (ev.type == xfixes_event_base + XFixesSelectionNotify) {
                    XFixesSelectionNotifyEvent *sev = (XFixesSelectionNotifyEvent *)&ev;
                    if (sev->selection == xa_primary) {
                        check_and_update_primary();
                    }
                }
            }
        }
    }

    if (fd_primary >= 0) { close(fd_primary); fd_primary = -1; }
    if (fd_seq     >= 0) { close(fd_seq);     fd_seq     = -1; }
    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);
    return 0;
}

/* Entry point — parse argv, open X11 display (XWayland), intern atoms,
 * and dispatch to the appropriate sub-function.
 *
 * Modes (first matching flag wins):
 *   (default)          Daemon: monitor PRIMARY via XFixes owner-change events.
 *   --oneshot          Print current PRIMARY text and exit.
 *   --get-clipboard    Print clipboard (CLIPBOARD) text and exit.
 *   --copy-clipboard   Read stdin, take clipboard ownership, serve paste requests.
 *   --clear-primary    Clear PRIMARY by setting its owner to None.
 *   --help / -h        Print usage to stderr and exit.
 *
 * A positional non-flag argument sets cache_dir (used by daemon mode). */
int main(int argc, char *argv[]) {
    const char *cache_dir_arg = NULL;
    bool oneshot = false;
    bool get_clipboard = false;
    bool copy_clipboard = false;
    bool clear_primary = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--oneshot") == 0)
            oneshot = true;
        else if (strcmp(argv[i], "--get-clipboard") == 0)
            get_clipboard = true;
        else if (strcmp(argv[i], "--copy-clipboard") == 0)
            copy_clipboard = true;
        else if (strcmp(argv[i], "--clear-primary") == 0)
            clear_primary = true;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "Usage: %s [cache_dir] [--oneshot|--get-clipboard|--copy-clipboard|--clear-primary]\n"
                "XWayland selection monitor and clipboard helper for zsh-edit-select.\n\n"
                "  (default)         Daemon mode — monitor PRIMARY selection\n"
                "  --oneshot         Print current PRIMARY and exit\n"
                "  --get-clipboard   Print clipboard contents and exit\n"
                "  --copy-clipboard  Read stdin, set as clipboard\n"
                "  --clear-primary   Clear PRIMARY selection\n",
                argv[0]);
            return 0;
        } else {
            cache_dir_arg = argv[i];
        }
    }

    dpy = XOpenDisplay(NULL);
    if (!dpy) {
        fprintf(stderr, "Cannot open X11 display (XWayland not available?)\n");
        return 1;
    }

    /* Intern the standard X11 selection atoms for conversion requests. */
    root = DefaultRootWindow(dpy);
    xa_primary = XInternAtom(dpy, "PRIMARY", False);
    xa_clipboard = XInternAtom(dpy, "CLIPBOARD", False);
    xa_utf8_string = XInternAtom(dpy, "UTF8_STRING", False);
    xa_targets = XInternAtom(dpy, "TARGETS", False);

    int ret = 0;
    if (oneshot)
        ret = run_oneshot();
    else if (get_clipboard)
        ret = run_get_clipboard();
    else if (copy_clipboard)
        ret = run_copy_clipboard();
    else if (clear_primary)
        ret = run_clear_primary();
    else
        ret = run_daemon(cache_dir_arg);

    XCloseDisplay(dpy);
    return ret;
}
