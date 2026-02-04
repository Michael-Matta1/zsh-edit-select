// Copyright (c) 2025 Michael Matta
// Version: 0.4.7
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// X11 XFixes-based PRIMARY selection monitor for zsh-edit-select
//
// Compile: gcc -O2 zes-selection-monitor.c -o zes-selection-monitor -lX11 -lXfixes
// Usage: zes-selection-monitor [cache_dir] [--oneshot]

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <time.h>
#include <sys/select.h>  // For fd_set, FD_ZERO, FD_SET, select()
#include <sys/time.h>    // For struct timeval

#ifdef __linux__
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/Xfixes.h>
#endif

#define CACHE_DIR_TEMPLATE "%s/.cache/zsh-edit-select"
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "monitor.pid"
#define MAX_SELECTION_SIZE (1024 * 1024)  // 1MB max

static volatile sig_atomic_t running = 1;
static char cache_dir[512];
static char primary_path[560];
static char seq_path[560];
static char pid_path[560];

static void signal_handler(int sig) {
    (void)sig;
    running = 0;
}

static int ensure_cache_dir(const char *dir) {
    if (dir && dir[0]) {
        snprintf(cache_dir, sizeof(cache_dir), "%s", dir);
    } else {
        const char *home = getenv("HOME");
        if (!home) return -1;
        snprintf(cache_dir, sizeof(cache_dir), CACHE_DIR_TEMPLATE, home);
    }

    snprintf(primary_path, sizeof(primary_path), "%s/%s", cache_dir, PRIMARY_FILE);
    snprintf(seq_path, sizeof(seq_path), "%s/%s", cache_dir, SEQ_FILE);
    snprintf(pid_path, sizeof(pid_path), "%s/%s", cache_dir, PID_FILE);

    struct stat st;
    if (stat(cache_dir, &st) == -1) {
        if (mkdir(cache_dir, 0700) == -1 && errno != EEXIST) {
            return -1;
        }
    }
    return 0;
}

static void write_sequence(unsigned long seq) {
    int fd = open(seq_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        char buf[24];
        int len = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t ret = write(fd, buf, len);
        (void)ret;
        fsync(fd);
        close(fd);
    }
}

static void write_primary(const char *data, size_t len, unsigned long seq) {
    int fd = open(primary_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;

    if (len > 0 && data) {
        ssize_t ret = write(fd, data, len);
        (void)ret;
    }
    fsync(fd);
    close(fd);

    write_sequence(seq);  // Signal after data is written
}

#ifdef __linux__
static int read_selection(Display *d, Window w, Atom selection, Atom target,
                          char **out_data, size_t *out_len) {
    Atom prop = XInternAtom(d, "ZES_SEL", False);

    XConvertSelection(d, selection, target, prop, w, CurrentTime);
    XFlush(d);

    for (int i = 0; i < 100; i++) {
        XEvent ev;
        if (XCheckTypedWindowEvent(d, w, SelectionNotify, &ev)) {
            if (ev.xselection.property == None) {
                return -1;
            }

            Atom actual_type;
            int actual_format;
            unsigned long nitems, bytes_after;
            unsigned char *data = NULL;

            if (XGetWindowProperty(d, w, prop, 0, MAX_SELECTION_SIZE/4, True,
                                   AnyPropertyType, &actual_type, &actual_format,
                                   &nitems, &bytes_after, &data) == Success) {
                if (data && nitems > 0) {
                    *out_data = malloc(nitems + 1);
                    if (*out_data) {
                        memcpy(*out_data, data, nitems);
                        (*out_data)[nitems] = '\0';
                        *out_len = nitems;
                    }
                    XFree(data);
                    return 0;
                }
                if (data) XFree(data);
            }
            return -1;
        }
        if (i < 5) {
            usleep(500);
        } else if (i < 20) {
            usleep(2000);
        } else {
            usleep(5000);
        }
    }
    return -1;
}

static int oneshot_mode(void) {
    Display *d = XOpenDisplay(NULL);
    if (!d) {
        fprintf(stderr, "Cannot open X display\n");
        return 1;
    }

    Window w = XCreateSimpleWindow(d, DefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0);
    Atom primary = XInternAtom(d, "PRIMARY", False);
    Atom utf8 = XInternAtom(d, "UTF8_STRING", False);

    char *data = NULL;
    size_t len = 0;

    if (read_selection(d, w, primary, utf8, &data, &len) == 0 && data) {
        fwrite(data, 1, len, stdout);
        free(data);
    }

    XDestroyWindow(d, w);
    XCloseDisplay(d);
    return 0;
}

static int daemon_mode(const char *cache_dir_arg) {
    Display *d = XOpenDisplay(NULL);
    if (!d) {
        fprintf(stderr, "Cannot open X display\n");
        return 1;
    }

    int xfixes_event_base, xfixes_error_base;
    if (!XFixesQueryExtension(d, &xfixes_event_base, &xfixes_error_base)) {
        fprintf(stderr, "XFixes extension not available\n");
        XCloseDisplay(d);
        return 1;
    }

    Window w = XCreateSimpleWindow(d, DefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0);
    Atom primary = XInternAtom(d, "PRIMARY", False);
    Atom utf8 = XInternAtom(d, "UTF8_STRING", False);

    XFixesSelectSelectionInput(d, w, primary,
        XFixesSetSelectionOwnerNotifyMask |
        XFixesSelectionWindowDestroyNotifyMask |
        XFixesSelectionClientCloseNotifyMask);

    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "Cannot create cache directory\n");
        XDestroyWindow(d, w);
        XCloseDisplay(d);
        return 1;
    }

    if (daemon(0, 0) != 0) {
        perror("daemon");
        return 1;
    }

    {
        FILE *f = fopen(pid_path, "w");
        if (f) {
            fprintf(f, "%d\n", getpid());
            fclose(f);
        }
    }

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);

    unsigned long seq = (unsigned long)time(NULL);

    {
        char *data = NULL;
        size_t len = 0;
        if (read_selection(d, w, primary, utf8, &data, &len) == 0) {
            write_primary(data, len, seq);
            free(data);
        } else {
            write_primary("", 0, seq);
        }
    }

    while (running) {
        XEvent ev;

        int fd = ConnectionNumber(d);
        fd_set fds;
        struct timeval tv;

        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        tv.tv_sec = 1;
        tv.tv_usec = 0;

        if (XPending(d) == 0) {
            int ret = select(fd + 1, &fds, NULL, NULL, &tv);
            if (ret <= 0) continue;
        }

        XNextEvent(d, &ev);

        if (ev.type == xfixes_event_base + XFixesSelectionNotify) {
            XFixesSelectionNotifyEvent *sev = (XFixesSelectionNotifyEvent *)&ev;

            if (sev->selection == primary) {
                seq++;

                char *data = NULL;
                size_t len = 0;

                if (sev->owner == None) {
                    write_primary("", 0, seq);
                } else if (read_selection(d, w, primary, utf8, &data, &len) == 0) {
                    write_primary(data, len, seq);
                    free(data);
                } else {
                    write_primary("", 0, seq);
                }
            }
        }
    }

    XDestroyWindow(d, w);;
    XCloseDisplay(d);

    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);

    return 0;
}
#endif

int main(int argc, char *argv[]) {
#ifndef __linux__
    fprintf(stderr, "zes-selection-monitor requires Linux/X11\n");
    return 1;
#else
    if (!getenv("DISPLAY")) {
        fprintf(stderr, "DISPLAY not set\n");
        return 1;
    }

    const char *cache_dir_arg = NULL;
    int oneshot = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--oneshot") == 0) {
            oneshot = 1;
        } else if (argv[i][0] != '-') {
            cache_dir_arg = argv[i];
        }
    }

    if (oneshot) {
        return oneshot_mode();
    }

    return daemon_mode(cache_dir_arg);
#endif
}
