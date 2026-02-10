// Copyright (c) 2025 Michael Matta
// Version: 0.5.6
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// X11 XFixes-based PRIMARY selection monitor and clipboard helper for
// zsh-edit-select
//
// Compile: gcc -O3 zes-x11-selection-monitor.c -o zes-x11-selection-monitor
// -lX11 -lXfixes Usage: zes-x11-selection-monitor [cache_dir]
// [--oneshot|--get-clipboard|--copy-clipboard|--clear-primary]

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <stdbool.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xfixes.h>

#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "monitor.pid"
#define MAX_SELECTION_SIZE (1024 * 1024)

static volatile sig_atomic_t running = 1;
static char cache_dir[512];
static char primary_path[560];
static char seq_path[560];
static char pid_path[560];

static Display *dpy = NULL;
static Window root;
static Atom xa_primary;
static Atom xa_clipboard;
static Atom xa_utf8_string;
static Atom xa_targets;
static unsigned long seq_counter = 0;

static void signal_handler(int sig) {
    (void)sig;
    running = 0;
}

static int ensure_cache_dir(const char *dir) {
    if (dir && dir[0]) {
        snprintf(cache_dir, sizeof(cache_dir), "%s", dir);
    } else {
        const char *runtime = getenv("XDG_RUNTIME_DIR");
        if (!runtime) {
            const char *home = getenv("HOME");
            if (!home) return -1;
            snprintf(cache_dir, sizeof(cache_dir), "%s/.cache/zsh-edit-select", home);
        } else {
            snprintf(cache_dir, sizeof(cache_dir), "%s/zsh-edit-select-%d",
                     runtime, (int)getuid());
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

static void write_primary(const char *data, size_t len, unsigned long seq) {
    int fd = open(primary_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    if (len > 0 && data) {
        ssize_t r = write(fd, data, len);
        (void)r;
    }
    close(fd);

    fd = open(seq_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        char buf[24];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = write(fd, buf, n);
        (void)r;
        close(fd);
    }
}

static char *get_primary_selection(size_t *out_len) {
    Window owner = XGetSelectionOwner(dpy, xa_primary);
    if (owner == None) {
        *out_len = 0;
        return NULL;
    }

    Atom prop = XInternAtom(dpy, "ZES_SEL", False);
    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XConvertSelection(dpy, xa_primary, xa_utf8_string, prop, w, CurrentTime);
    XFlush(dpy);

    XEvent ev;
    bool got_notify = false;
    for (int i = 0; i < 100; i++) {
        if (XCheckTypedWindowEvent(dpy, w, SelectionNotify, &ev)) {
            got_notify = true;
            break;
        }
        if (i < 5) usleep(500);
        else if (i < 20) usleep(2000);
        else usleep(5000);
    }

    char *data = NULL;
    *out_len = 0;

    if (got_notify && ev.xselection.property != None) {
        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *xdata = NULL;

        if (XGetWindowProperty(dpy, w, prop, 0, MAX_SELECTION_SIZE / 4, True,
                               AnyPropertyType, &actual_type, &actual_format,
                               &nitems, &bytes_after, &xdata) == Success) {
            if (xdata && nitems > 0) {
                data = malloc(nitems + 1);
                if (data) {
                    memcpy(data, xdata, nitems);
                    data[nitems] = '\0';
                    *out_len = nitems;
                }
            }
            if (xdata) XFree(xdata);
        }
    }

    XDestroyWindow(dpy, w);
    return data;
}

static void check_and_update_primary(void) {
    size_t len = 0;
    char *sel = get_primary_selection(&len);

    // Always increment seq — even if content is same (handles reselect-same-text)
    seq_counter++;
    write_primary(sel ? sel : "", sel ? len : 0, seq_counter);
    free(sel);
}

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

static char *get_selection(Atom selection, size_t *out_len) {
    Window owner = XGetSelectionOwner(dpy, selection);
    if (owner == None) {
        *out_len = 0;
        return NULL;
    }

    Atom prop = (selection == xa_primary) ? XInternAtom(dpy, "ZES_SEL", False)
                                           : XInternAtom(dpy, "ZES_CLIP", False);
    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XConvertSelection(dpy, selection, xa_utf8_string, prop, w, CurrentTime);
    XFlush(dpy);

    XEvent ev;
    bool got_notify = false;
    for (int i = 0; i < 100; i++) {
        if (XCheckTypedWindowEvent(dpy, w, SelectionNotify, &ev)) {
            got_notify = true;
            break;
        }
        if (i < 5) usleep(500);
        else if (i < 20) usleep(2000);
        else usleep(5000);
    }

    char *data = NULL;
    *out_len = 0;

    if (got_notify && ev.xselection.property != None) {
        Atom actual_type;
        int actual_format;
        unsigned long nitems, bytes_after;
        unsigned char *xdata = NULL;

        if (XGetWindowProperty(dpy, w, prop, 0, MAX_SELECTION_SIZE / 4, True,
                               AnyPropertyType, &actual_type, &actual_format,
                               &nitems, &bytes_after, &xdata) == Success) {
            if (xdata && nitems > 0) {
                data = malloc(nitems + 1);
                if (data) {
                    memcpy(data, xdata, nitems);
                    data[nitems] = '\0';
                    *out_len = nitems;
                }
            }
            if (xdata) XFree(xdata);
        }
    }

    XDestroyWindow(dpy, w);
    return data;
}

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

static char *read_all_stdin(size_t *out_len) {
    size_t capacity = 4096, total = 0;
    char *buf = malloc(capacity);
    if (!buf) return NULL;

    while (1) {
        if (total + 4096 > capacity) {
            capacity *= 2;
            if (capacity > MAX_SELECTION_SIZE) break;
            char *nb = realloc(buf, capacity);
            if (!nb) { free(buf); return NULL; }
            buf = nb;
        }
        ssize_t n = read(STDIN_FILENO, buf + total, 4096);
        if (n > 0) total += n;
        else break;
    }
    *out_len = total;
    return buf;
}

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
    }

    XSendEvent(dpy, req->requestor, False, 0, &response);
    XFlush(dpy);
    return 0;
}

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

    pid_t pid = fork();
    if (pid < 0) {
        free(data);
        XDestroyWindow(dpy, w);
        return 1;
    }
    if (pid > 0) {
        _exit(0);
    }

    setsid();
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, SIG_IGN);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    int timeout_count = 0;
    bool selection_served = false;
    while (running && timeout_count < 500) {
        while (XPending(dpy) > 0) {
            XEvent ev;
            XNextEvent(dpy, &ev);

            if (ev.type == SelectionRequest) {
                handle_selection_request(&ev.xselectionrequest, data, data_len);
                selection_served = true;
                timeout_count = 0;
            } else if (ev.type == SelectionClear) {
                running = 0;
                break;
            }
        }

        if (!running) break;

        usleep(100000);
        if (!selection_served) timeout_count++;
    }

    free(data);
    XDestroyWindow(dpy, w);
    _exit(0);
}

static int run_clear_primary(void) {
    Window w = XCreateSimpleWindow(dpy, root, 0, 0, 1, 1, 0, 0, 0);
    XSetSelectionOwner(dpy, xa_primary, None, CurrentTime);
    XFlush(dpy);
    XDestroyWindow(dpy, w);
    return 0;
}

static int run_daemon(const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "Cannot create cache directory\n");
        return 1;
    }

    int xfixes_event_base, xfixes_error_base;
    if (!XFixesQueryExtension(dpy, &xfixes_event_base, &xfixes_error_base)) {
        fprintf(stderr, "XFixes extension not available\n");
        return 1;
    }

    XFixesSelectSelectionInput(dpy, root, xa_primary,
                                XFixesSetSelectionOwnerNotifyMask);
    XFlush(dpy);

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

    check_and_update_primary();

    while (running) {
        XEvent ev;
        XNextEvent(dpy, &ev);

        if (ev.type == xfixes_event_base + XFixesSelectionNotify) {
            XFixesSelectionNotifyEvent *sev = (XFixesSelectionNotifyEvent *)&ev;
            if (sev->selection == xa_primary) {
                check_and_update_primary();
            }
        }
    }

    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);
    return 0;
}

int main(int argc, char *argv[]) {
    if (!getenv("DISPLAY")) {
        fprintf(stderr, "DISPLAY not set\n");
        return 1;
    }

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
                "X11 selection monitor and clipboard helper for zsh-edit-select.\n\n"
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
        fprintf(stderr, "Cannot open X display\n");
        return 1;
    }

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
