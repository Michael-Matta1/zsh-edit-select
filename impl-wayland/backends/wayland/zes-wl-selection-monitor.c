// Copyright (c) 2025 Michael Matta
// Version: 0.5.3
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// Wayland PRIMARY selection monitor and clipboard helper for zsh-edit-select.
// Uses zwp_primary_selection_unstable_v1 for PRIMARY and wl_data_device for
// clipboard, completely replacing wl-clipboard (wl-paste / wl-copy) to
// eliminate process-spawn lag that causes typing delays.
//
// Build: make  (uses the Makefile in this directory)
//
// Modes:
//   zes-wl-selection-monitor <cache_dir>         Daemon: monitor PRIMARY
//   zes-wl-selection-monitor --oneshot            Print current PRIMARY
//   zes-wl-selection-monitor --get-clipboard      Print clipboard contents
//   zes-wl-selection-monitor --copy-clipboard     Read stdin, set clipboard
//   zes-wl-selection-monitor --clear-primary      Clear PRIMARY selection

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
#include <poll.h>
#include <stdbool.h>
#include <sys/mman.h>
#include <wayland-client.h>

#include "primary-selection-unstable-v1-client-protocol.h"

/* xdg-shell stable protocol — inline minimal definitions so we don't
   need an extra generated header just for the daemon surface. */
#include "xdg-shell-client-protocol.h"

#define CACHE_DIR_TEMPLATE "%s/.cache/zsh-edit-select"
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "monitor.pid"
#define MAX_SELECTION_SIZE (1024 * 1024)
#define MAX_CLIPBOARD_SIZE (4 * 1024 * 1024)

static volatile sig_atomic_t running = 1;
static char cache_dir[512];
static char primary_path[560];
static char seq_path[560];
static char pid_path[560];

/* Wayland globals */
static struct wl_display *wl_dpy = NULL;
static struct wl_registry *wl_reg = NULL;
static struct wl_seat *wl_seat_obj = NULL;
static struct wl_data_device_manager *wl_ddm = NULL;
static struct wl_data_device *wl_dd = NULL;
static struct zwp_primary_selection_device_manager_v1 *ps_manager = NULL;
static struct zwp_primary_selection_device_v1 *ps_device = NULL;
static struct zwp_primary_selection_offer_v1 *current_ps_offer = NULL;
static struct wl_data_offer *current_clipboard_offer = NULL;
static unsigned long seq_counter = 0;
static bool ps_has_text = false;
static bool clip_has_text = false;

/* Surface globals — Mutter/GNOME only delivers PRIMARY selection events
   to clients with a mapped surface.  The daemon creates a permanent 1x1
   transparent xdg_toplevel at startup.  On wlroots/KDE this is harmless;
   on Mutter it is required for event delivery. */
static struct wl_compositor *wl_comp = NULL;
static struct wl_shm *wl_shm_obj = NULL;
static struct xdg_wm_base *xdg_wmbase = NULL;
static struct wl_surface *daemon_surface = NULL;
static struct xdg_surface *daemon_xdg_surface = NULL;
static struct xdg_toplevel *daemon_xdg_toplevel = NULL;
static bool surface_configured = false;
static struct wl_buffer *daemon_buffer = NULL;

/* Mode flags — controls handler behavior */
static bool is_daemon_mode = false;
static bool got_selection = false; /* one-shot: set when selection event arrives */
static char *last_known_content = NULL;
static size_t last_known_len = 0;

/* For --copy-clipboard: data source serving */
static struct wl_data_source *copy_source = NULL;
static char *copy_data = NULL;
static size_t copy_data_len = 0;
static bool copy_done = false;

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
            snprintf(cache_dir, sizeof(cache_dir), CACHE_DIR_TEMPLATE, home);
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

/* Forward declaration — needed because check_and_update_primary() is
   defined before read_ps_offer() for logical grouping. */
static char *read_ps_offer(struct zwp_primary_selection_offer_v1 *offer,
                           size_t *out_len);

static void write_primary(const char *data, size_t len, unsigned long seq) {
    /* Write primary content */
    int fd = open(primary_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return;
    if (len > 0 && data) {
        ssize_t r = write(fd, data, len);
        (void)r;
    }
    close(fd);

    /* Write sequence number — the shell detects changes via mtime on
       this file, so it MUST be written after primary content. */
    fd = open(seq_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        char buf[24];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = write(fd, buf, n);
        (void)r;
        close(fd);
    }
}

/* Helper: update last_known_content cache and write to disk if changed.
 * Returns true if content changed. Centralizes the comparison logic
 * that was previously duplicated in 3+ places.
 *
 * CRITICAL: Always increments seq_counter on selection events, even if content is same.
 * This handles: select "world" → deselect → select "world" again.
 * The seq_counter represents "selection event occurred", not "content changed". */
static bool check_and_update_primary(void) {
    if (!current_ps_offer || !ps_has_text) {
        if (last_known_content) {
            seq_counter++;
            write_primary("", 0, seq_counter);
            free(last_known_content);
            last_known_content = NULL;
            last_known_len = 0;
            return true;
        }
        return false;
    }

    size_t len = 0;
    char *sel = read_ps_offer(current_ps_offer, &len);

    /* Always increment seq_counter and write - selection owner changed */
    seq_counter++;
    write_primary(sel ? sel : "", sel ? len : 0, seq_counter);

    bool changed = false;
    if (!sel && last_known_content)
        changed = true;
    else if (sel && !last_known_content)
        changed = true;
    else if (sel && last_known_content)
        changed = (len != last_known_len || memcmp(sel, last_known_content, len) != 0);

    free(last_known_content);
    if (sel && len > 0) {
        last_known_content = malloc(len);
        if (last_known_content) {
            memcpy(last_known_content, sel, len);
            last_known_len = len;
        } else {
            last_known_len = 0;
        }
    } else {
        last_known_content = NULL;
        last_known_len = 0;
    }

    free(sel);
    return changed;
}

/* ------------------------------------------------------------------ */
/* Utility: read text from an fd with poll timeout                     */
/* ------------------------------------------------------------------ */
static char *read_fd_with_timeout(int fd, size_t *out_len, size_t max_size,
                                   int initial_timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    char *buf = NULL;
    size_t total = 0, capacity = 0;
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    int timeout_ms = initial_timeout_ms;

    while (1) {
        int ret = poll(&pfd, 1, timeout_ms);
        if (ret <= 0) break;
        if ((pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) &&
            !(pfd.revents & POLLIN))
            break;

        if (pfd.revents & POLLIN) {
            if (total + 4096 > capacity) {
                capacity = capacity ? capacity * 2 : 4096;
                if (capacity > max_size) break;
                char *nb = realloc(buf, capacity + 1);
                if (!nb) break;
                buf = nb;
            }
            ssize_t n = read(fd, buf + total, 4096);
            if (n > 0) total += n;
            else if (n == 0) break;
            else if (errno != EAGAIN && errno != EWOULDBLOCK) break;
        }
        timeout_ms = 100;
    }

    if (buf) { buf[total] = '\0'; }
    *out_len = total;
    return buf;
}

/* ------------------------------------------------------------------ */
/* Read text from a primary selection offer                            */
/* ------------------------------------------------------------------ */
static char *read_ps_offer(struct zwp_primary_selection_offer_v1 *offer,
                            size_t *out_len) {
    int fds[2];
    if (pipe(fds) == -1) return NULL;
    zwp_primary_selection_offer_v1_receive(
        offer, "text/plain;charset=utf-8", fds[1]);
    wl_display_flush(wl_dpy);
    close(fds[1]);
    char *data = read_fd_with_timeout(fds[0], out_len, MAX_SELECTION_SIZE, 500);
    close(fds[0]);
    return data;
}

/* ------------------------------------------------------------------ */
/* Read text from a clipboard data offer                               */
/* ------------------------------------------------------------------ */
static char *read_clip_offer(struct wl_data_offer *offer, size_t *out_len) {
    int fds[2];
    if (pipe(fds) == -1) return NULL;
    wl_data_offer_receive(offer, "text/plain;charset=utf-8", fds[1]);
    wl_display_flush(wl_dpy);
    close(fds[1]);
    char *data = read_fd_with_timeout(fds[0], out_len, MAX_CLIPBOARD_SIZE, 500);
    close(fds[0]);
    return data;
}

/* ===== PRIMARY SELECTION LISTENERS ================================ */

static void ps_offer_handle_offer(void *data,
        struct zwp_primary_selection_offer_v1 *offer,
        const char *mime_type) {
    (void)data; (void)offer;
    if (strcmp(mime_type, "text/plain;charset=utf-8") == 0 ||
        strcmp(mime_type, "text/plain") == 0 ||
        strcmp(mime_type, "UTF8_STRING") == 0 ||
        strcmp(mime_type, "TEXT") == 0 ||
        strcmp(mime_type, "STRING") == 0)
        ps_has_text = true;
}

static const struct zwp_primary_selection_offer_v1_listener ps_offer_listener = {
    .offer = ps_offer_handle_offer,
};

static void ps_device_handle_data_offer(void *data,
        struct zwp_primary_selection_device_v1 *dev,
        struct zwp_primary_selection_offer_v1 *offer) {
    (void)data; (void)dev;
    ps_has_text = false;
    zwp_primary_selection_offer_v1_add_listener(offer, &ps_offer_listener, NULL);
}

static void ps_device_handle_selection(void *data,
        struct zwp_primary_selection_device_v1 *dev,
        struct zwp_primary_selection_offer_v1 *offer) {
    (void)data; (void)dev;
    if (current_ps_offer && current_ps_offer != offer)
        zwp_primary_selection_offer_v1_destroy(current_ps_offer);
    current_ps_offer = offer;
    seq_counter++;
    got_selection = true;

    /* In daemon mode, read the offer immediately and write to cache.
       In other modes (oneshot etc), just store the offer reference
       and let the caller read it — avoids double-read bugs where
       the second read times out because the offering client already
       served the first request. */
    if (!is_daemon_mode) return;

    if (!offer || !ps_has_text) {
        if (last_known_content) {
            seq_counter++;
            write_primary("", 0, seq_counter);
            free(last_known_content);
            last_known_content = NULL;
            last_known_len = 0;
        }
        return;
    }

    size_t len = 0;
    char *sel = read_ps_offer(offer, &len);

    /* Only update cache if content actually changed. */
    bool changed = false;
    if (!sel && last_known_content)
        changed = true;
    else if (sel && !last_known_content)
        changed = true;
    else if (sel && last_known_content)
        changed = (len != last_known_len || memcmp(sel, last_known_content, len) != 0);

    if (changed) {
        seq_counter++;
        write_primary(sel ? sel : "", sel ? len : 0, seq_counter);
        free(last_known_content);
        if (sel && len > 0) {
            last_known_content = malloc(len);
            if (last_known_content) {
                memcpy(last_known_content, sel, len);
                last_known_len = len;
            } else { last_known_len = 0; }
        } else {
            last_known_content = NULL;
            last_known_len = 0;
        }
    }

    free(sel);
}

static const struct zwp_primary_selection_device_v1_listener ps_device_listener = {
    .data_offer = ps_device_handle_data_offer,
    .selection = ps_device_handle_selection,
};

/* ===== CLIPBOARD (wl_data_device) LISTENERS ======================= */

static void clip_offer_handle_offer(void *data, struct wl_data_offer *offer,
                                     const char *mime_type) {
    (void)data; (void)offer;
    if (strcmp(mime_type, "text/plain;charset=utf-8") == 0 ||
        strcmp(mime_type, "text/plain") == 0)
        clip_has_text = true;
}

static const struct wl_data_offer_listener clip_offer_listener = {
    .offer = clip_offer_handle_offer,
};

static void dd_handle_data_offer(void *data, struct wl_data_device *dev,
                                  struct wl_data_offer *offer) {
    (void)data; (void)dev;
    clip_has_text = false;
    wl_data_offer_add_listener(offer, &clip_offer_listener, NULL);
}

static void dd_handle_enter(void *d, struct wl_data_device *dev,
                             uint32_t s, struct wl_surface *su,
                             wl_fixed_t x, wl_fixed_t y,
                             struct wl_data_offer *o) {
    (void)d;(void)dev;(void)s;(void)su;(void)x;(void)y;(void)o;
}
static void dd_handle_leave(void *d, struct wl_data_device *dev) {
    (void)d;(void)dev;
}
static void dd_handle_motion(void *d, struct wl_data_device *dev,
                              uint32_t t, wl_fixed_t x, wl_fixed_t y) {
    (void)d;(void)dev;(void)t;(void)x;(void)y;
}
static void dd_handle_drop(void *d, struct wl_data_device *dev) {
    (void)d;(void)dev;
}

static void dd_handle_selection(void *data, struct wl_data_device *dev,
                                 struct wl_data_offer *offer) {
    (void)data; (void)dev;
    if (current_clipboard_offer && current_clipboard_offer != offer)
        wl_data_offer_destroy(current_clipboard_offer);
    current_clipboard_offer = offer;
}

static const struct wl_data_device_listener dd_listener = {
    .data_offer = dd_handle_data_offer,
    .enter      = dd_handle_enter,
    .leave      = dd_handle_leave,
    .motion     = dd_handle_motion,
    .drop       = dd_handle_drop,
    .selection  = dd_handle_selection,
};

/* ===== DATA SOURCE (for --copy-clipboard) ========================= */

static void ds_handle_target(void *data, struct wl_data_source *src,
                              const char *mime_type) {
    (void)data;(void)src;(void)mime_type;
}

static void ds_handle_send(void *data, struct wl_data_source *src,
                            const char *mime_type, int32_t fd) {
    (void)data; (void)src; (void)mime_type;
    if (copy_data && copy_data_len > 0) {
        size_t written = 0;
        while (written < copy_data_len) {
            ssize_t n = write(fd, copy_data + written, copy_data_len - written);
            if (n <= 0) break;
            written += n;
        }
    }
    close(fd);
}

static void ds_handle_cancelled(void *data, struct wl_data_source *src) {
    (void)data;
    wl_data_source_destroy(src);
    copy_source = NULL;
    copy_done = true;
}

static const struct wl_data_source_listener ds_listener = {
    .target    = ds_handle_target,
    .send      = ds_handle_send,
    .cancelled = ds_handle_cancelled,
};

/* ===== PRIMARY SELECTION SOURCE (for --clear-primary) ============= */
/* Kept for potential future use with compositors that need a source */

/* ===== XDG-SHELL / SURFACE LISTENERS ============================== */

static void xdg_wm_base_ping(void *data, struct xdg_wm_base *base,
                              uint32_t serial) {
    (void)data;
    xdg_wm_base_pong(base, serial);
}

static const struct xdg_wm_base_listener xdg_wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

static void xdg_surface_handle_configure(void *data,
        struct xdg_surface *surface, uint32_t serial) {
    (void)data;
    xdg_surface_ack_configure(surface, serial);
    surface_configured = true;
}

static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_handle_configure,
};

static void xdg_toplevel_handle_configure(void *data,
        struct xdg_toplevel *toplevel, int32_t w, int32_t h,
        struct wl_array *states) {
    (void)data;(void)toplevel;(void)w;(void)h;(void)states;
}

static void xdg_toplevel_handle_close(void *data,
        struct xdg_toplevel *toplevel) {
    (void)data;(void)toplevel;
    running = 0;
}

static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_toplevel_handle_configure,
    .close     = xdg_toplevel_handle_close,
};

/* ===== REGISTRY =================================================== */

static void registry_handle_global(void *data, struct wl_registry *reg,
                                    uint32_t name, const char *interface,
                                    uint32_t version) {
    (void)data; (void)version;
    if (strcmp(interface, "wl_seat") == 0) {
        wl_seat_obj = wl_registry_bind(reg, name, &wl_seat_interface, 2);
    } else if (strcmp(interface,
                "zwp_primary_selection_device_manager_v1") == 0) {
        ps_manager = wl_registry_bind(reg, name,
            &zwp_primary_selection_device_manager_v1_interface, 1);
    } else if (strcmp(interface, "wl_data_device_manager") == 0) {
        wl_ddm = wl_registry_bind(reg, name,
            &wl_data_device_manager_interface,
            version < 3 ? version : 3);
    } else if (strcmp(interface, "wl_compositor") == 0) {
        wl_comp = wl_registry_bind(reg, name, &wl_compositor_interface,
                                    version < 4 ? version : 4);
    } else if (strcmp(interface, "xdg_wm_base") == 0) {
        xdg_wmbase = wl_registry_bind(reg, name, &xdg_wm_base_interface, 1);
        xdg_wm_base_add_listener(xdg_wmbase, &xdg_wm_base_listener, NULL);
    } else if (strcmp(interface, "wl_shm") == 0) {
        wl_shm_obj = wl_registry_bind(reg, name, &wl_shm_interface, 1);
    }
}

static void registry_handle_global_remove(void *data, struct wl_registry *reg,
                                           uint32_t name) {
    (void)data;(void)reg;(void)name;
}

static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

/* ===== HELPERS ==================================================== */

static int wayland_connect(void) {
    wl_dpy = wl_display_connect(NULL);
    if (!wl_dpy) {
        fprintf(stderr, "Cannot connect to Wayland display\n");
        return -1;
    }
    wl_reg = wl_display_get_registry(wl_dpy);
    wl_registry_add_listener(wl_reg, &registry_listener, NULL);
    wl_display_roundtrip(wl_dpy);
    return 0;
}

static void wayland_disconnect(void) {
    if (current_ps_offer) {
        zwp_primary_selection_offer_v1_destroy(current_ps_offer);
        current_ps_offer = NULL;
    }
    if (current_clipboard_offer) {
        wl_data_offer_destroy(current_clipboard_offer);
        current_clipboard_offer = NULL;
    }
    if (ps_device) {
        zwp_primary_selection_device_v1_destroy(ps_device);
        ps_device = NULL;
    }
    if (ps_manager) {
        zwp_primary_selection_device_manager_v1_destroy(ps_manager);
        ps_manager = NULL;
    }
    if (daemon_buffer) { wl_buffer_destroy(daemon_buffer); daemon_buffer = NULL; }
    if (daemon_xdg_toplevel) { xdg_toplevel_destroy(daemon_xdg_toplevel); daemon_xdg_toplevel = NULL; }
    if (daemon_xdg_surface) { xdg_surface_destroy(daemon_xdg_surface); daemon_xdg_surface = NULL; }
    if (daemon_surface) { wl_surface_destroy(daemon_surface); daemon_surface = NULL; }
    if (xdg_wmbase) { xdg_wm_base_destroy(xdg_wmbase); xdg_wmbase = NULL; }
    if (wl_comp) { wl_compositor_destroy(wl_comp); wl_comp = NULL; }
    if (wl_shm_obj) { wl_shm_destroy(wl_shm_obj); wl_shm_obj = NULL; }
    if (wl_dd) { wl_data_device_destroy(wl_dd); wl_dd = NULL; }
    if (wl_ddm) { wl_data_device_manager_destroy(wl_ddm); wl_ddm = NULL; }
    if (wl_seat_obj) { wl_seat_destroy(wl_seat_obj); wl_seat_obj = NULL; }
    if (wl_reg) { wl_registry_destroy(wl_reg); wl_reg = NULL; }
    if (wl_dpy) { wl_display_disconnect(wl_dpy); wl_dpy = NULL; }
}

/* Forward declaration */
static int create_daemon_surface(void);

/* ===== MODE: --oneshot ============================================ */
/* On Mutter/GNOME, selection events are only delivered to clients with
   keyboard focus.  Like wl-paste, we briefly create a tiny popup surface
   to gain focus, receive the current selection, read it, and exit.
   The surface is transparent and exists for only a few milliseconds. */

static int run_oneshot(const char *cache_dir_arg) {
    if (wayland_connect() != 0) return 1;
    if (!ps_manager || !wl_seat_obj) {
        fprintf(stderr, "Compositor missing primary-selection or seat\n");
        wayland_disconnect();
        return 1;
    }

    ps_device = zwp_primary_selection_device_manager_v1_get_device(
        ps_manager, wl_seat_obj);
    zwp_primary_selection_device_v1_add_listener(
        ps_device, &ps_device_listener, NULL);

    /* First try: a simple roundtrip (works on wlroots compositors
       that deliver selection events without focus). */
    got_selection = false;
    wl_display_roundtrip(wl_dpy);

    /* If we didn't get the selection event (Mutter), create a popup
       surface to gain keyboard focus, then dispatch events until
       the selection event arrives or we time out. */
    if (!got_selection && wl_comp && xdg_wmbase && wl_shm_obj) {
        create_daemon_surface();
        wl_display_roundtrip(wl_dpy);

        int wl_fd = wl_display_get_fd(wl_dpy);
        int attempts = 0;
        while (!got_selection && attempts < 50) {
            while (wl_display_prepare_read(wl_dpy) != 0)
                wl_display_dispatch_pending(wl_dpy);
            wl_display_flush(wl_dpy);
            struct pollfd pfd = { .fd = wl_fd, .events = POLLIN };
            int ret = poll(&pfd, 1, 100);
            if (ret > 0 && (pfd.revents & POLLIN)) {
                wl_display_read_events(wl_dpy);
                wl_display_dispatch_pending(wl_dpy);
            } else {
                wl_display_cancel_read(wl_dpy);
            }
            attempts++;
        }
    }

    /* Optionally set up cache paths for writing back to daemon cache */
    int have_cache = 0;
    if (cache_dir_arg && cache_dir_arg[0]) {
        if (ensure_cache_dir(cache_dir_arg) == 0)
            have_cache = 1;
    }

    if (current_ps_offer && ps_has_text) {
        size_t len = 0;
        char *data = read_ps_offer(current_ps_offer, &len);
        if (data && len > 0) {
            fwrite(data, 1, len, stdout);
            /* Update cache files so daemon-based detection stays in sync.
               This is critical for Mutter where the daemon doesn't receive
               PRIMARY events due to focus gating — the oneshot fallback
               keeps the cache up to date. */
            if (have_cache) {
                seq_counter++;
                write_primary(data, len, seq_counter);
            }
        }
        free(data);
    } else if (have_cache) {
        /* No selection available — write empty to cache so the shell
           knows the selection was cleared (matches daemon behavior). */
        seq_counter++;
        write_primary("", 0, seq_counter);
    }
    wayland_disconnect();
    return 0;
}

/* ===== MODE: --get-clipboard ====================================== */

static int run_get_clipboard(void) {
    if (wayland_connect() != 0) return 1;
    if (!wl_ddm || !wl_seat_obj) {
        fprintf(stderr, "Compositor missing wl_data_device_manager or seat\n");
        wayland_disconnect();
        return 1;
    }
    wl_dd = wl_data_device_manager_get_data_device(wl_ddm, wl_seat_obj);
    wl_data_device_add_listener(wl_dd, &dd_listener, NULL);
    wl_display_roundtrip(wl_dpy);

    if (current_clipboard_offer && clip_has_text) {
        size_t len = 0;
        char *data = read_clip_offer(current_clipboard_offer, &len);
        if (data && len > 0) fwrite(data, 1, len, stdout);
        free(data);
    }
    wayland_disconnect();
    return 0;
}

/* ===== MODE: --copy-clipboard ===================================== */

static char *read_all_stdin(size_t *out_len) {
    size_t capacity = 4096, total = 0;
    char *buf = malloc(capacity);
    if (!buf) return NULL;

    while (1) {
        if (total + 4096 > capacity) {
            capacity *= 2;
            if (capacity > MAX_CLIPBOARD_SIZE) break;
            char *nb = realloc(buf, capacity);
            if (!nb) break;
            buf = nb;
        }
        ssize_t n = read(STDIN_FILENO, buf + total, 4096);
        if (n > 0) total += n;
        else break;
    }
    *out_len = total;
    return buf;
}

static int run_copy_clipboard(void) {
    copy_data = read_all_stdin(&copy_data_len);
    if (!copy_data || copy_data_len == 0) {
        free(copy_data);
        return 1;
    }

    if (wayland_connect() != 0) { free(copy_data); return 1; }
    if (!wl_ddm || !wl_seat_obj) {
        fprintf(stderr, "Compositor missing wl_data_device_manager or seat\n");
        free(copy_data); wayland_disconnect(); return 1;
    }

    wl_dd = wl_data_device_manager_get_data_device(wl_ddm, wl_seat_obj);
    wl_data_device_add_listener(wl_dd, &dd_listener, NULL);

    copy_source = wl_data_device_manager_create_data_source(wl_ddm);
    wl_data_source_offer(copy_source, "text/plain;charset=utf-8");
    wl_data_source_offer(copy_source, "text/plain");
    wl_data_source_offer(copy_source, "UTF8_STRING");
    wl_data_source_offer(copy_source, "STRING");
    wl_data_source_add_listener(copy_source, &ds_listener, NULL);

    wl_data_device_set_selection(wl_dd, copy_source, 0);
    wl_display_flush(wl_dpy);

    /* Fork a child that stays alive to serve paste requests until another
       app takes the clipboard.  Parent returns immediately so the shell
       is never blocked. */
    pid_t pid = fork();
    if (pid < 0) {
        free(copy_data); wayland_disconnect(); return 1;
    }
    if (pid > 0) {
        /* Parent: do NOT cleanup wayland — child owns the connection */
        _exit(0);
    }

    /* Child: background clipboard server */
    setsid();
    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, SIG_IGN);

    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    int wl_fd = wl_display_get_fd(wl_dpy);

    while (running && !copy_done) {
        while (wl_display_prepare_read(wl_dpy) != 0)
            wl_display_dispatch_pending(wl_dpy);

        if (wl_display_flush(wl_dpy) == -1 && errno != EAGAIN) {
            wl_display_cancel_read(wl_dpy);
            break;
        }

        struct pollfd pfd = { .fd = wl_fd, .events = POLLIN };
        int ret = poll(&pfd, 1, 5000);

        if (ret < 0) {
            wl_display_cancel_read(wl_dpy);
            if (errno == EINTR) continue;
            break;
        }
        if (ret == 0) { wl_display_cancel_read(wl_dpy); continue; }

        if (pfd.revents & POLLIN) {
            if (wl_display_read_events(wl_dpy) == -1) break;
            wl_display_dispatch_pending(wl_dpy);
        } else {
            wl_display_cancel_read(wl_dpy);
        }

        if (wl_display_get_error(wl_dpy) != 0) break;
    }

    free(copy_data);
    wayland_disconnect();
    _exit(0);
}

/* ===== MODE: --clear-primary ====================================== */

static int run_clear_primary(void) {
    if (wayland_connect() != 0) return 1;
    if (!ps_manager || !wl_seat_obj) {
        wayland_disconnect();
        return 1;
    }
    ps_device = zwp_primary_selection_device_manager_v1_get_device(
        ps_manager, wl_seat_obj);

    /* Set NULL selection to clear PRIMARY */
    zwp_primary_selection_device_v1_set_selection(ps_device, NULL, 0);
    wl_display_roundtrip(wl_dpy);

    wayland_disconnect();
    return 0;
}

/* ===== MODE: daemon =============================================== */

/* Create a tiny 1x1 pixel surface so that compositors like Mutter/GNOME
   that require a mapped surface will deliver PRIMARY selection events.
   The surface is permanent (never destroyed) to avoid focus-stealing.
   On wlroots/KDE this is harmless; on Mutter it is required. */
static int create_daemon_surface(void) {
    if (!wl_comp || !xdg_wmbase || !wl_shm_obj) return -1;

    /* Create 1x1 pixel SHM buffer (fully transparent ARGB) */
    int stride = 4, size = stride;
    int shm_fd = -1;
#ifdef __linux__
    shm_fd = memfd_create("zes-buf", 0);
#endif
    if (shm_fd < 0) {
        char name[] = "/zes-buf-XXXXXX";
        shm_fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL, 0600);
        if (shm_fd >= 0) shm_unlink(name);
    }
    if (shm_fd < 0) return -1;
    if (ftruncate(shm_fd, size) < 0) { close(shm_fd); return -1; }
    struct wl_shm_pool *pool = wl_shm_create_pool(wl_shm_obj, shm_fd, size);
    daemon_buffer = wl_shm_pool_create_buffer(
        pool, 0, 1, 1, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(shm_fd);
    if (!daemon_buffer) return -1;

    daemon_surface = wl_compositor_create_surface(wl_comp);
    if (!daemon_surface) return -1;

    /* Set empty input region — the surface cannot receive pointer or
       keyboard events, preventing it from stealing focus from other
       windows.  Selection events still arrive via the seat device. */
    struct wl_region *empty = wl_compositor_create_region(wl_comp);
    wl_surface_set_input_region(daemon_surface, empty);
    wl_region_destroy(empty);

    daemon_xdg_surface = xdg_wm_base_get_xdg_surface(xdg_wmbase,
                                                       daemon_surface);
    xdg_surface_add_listener(daemon_xdg_surface, &xdg_surface_listener,
                              NULL);

    daemon_xdg_toplevel = xdg_surface_get_toplevel(daemon_xdg_surface);
    xdg_toplevel_add_listener(daemon_xdg_toplevel, &xdg_toplevel_listener,
                               NULL);
    /* No title, no app_id — minimise compositor metadata */

    /* Initial commit to trigger the configure sequence */
    wl_surface_commit(daemon_surface);
    wl_display_roundtrip(wl_dpy);

    /* Attach 1x1 transparent pixel — maps the surface */
    wl_surface_attach(daemon_surface, daemon_buffer, 0, 0);
    wl_surface_damage(daemon_surface, 0, 0, 1, 1);
    wl_surface_commit(daemon_surface);

    /* Roundtrip to process configure + selection events */
    wl_display_roundtrip(wl_dpy);

    return 0;
}

static int run_daemon(const char *cache_dir_arg) {
    if (wayland_connect() != 0) return 1;
    if (!ps_manager) {
        fprintf(stderr,
                "Compositor does not support zwp_primary_selection_v1\n");
        wayland_disconnect();
        return 1;
    }
    if (!wl_seat_obj) {
        fprintf(stderr, "No seat found\n");
        wayland_disconnect();
        return 1;
    }

    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "Cannot create cache directory\n");
        wayland_disconnect();
        return 1;
    }

    is_daemon_mode = true;

    /* Write initial empty cache files BEFORE daemonizing so the shell
       never tries to read a non-existent file. */
    seq_counter = (unsigned long)time(NULL);
    write_primary("", 0, seq_counter);

    if (daemon(0, 0) != 0) {
        perror("daemon");
        wayland_disconnect();
        return 1;
    }

    {
        FILE *f = fopen(pid_path, "w");
        if (f) { fprintf(f, "%d\n", getpid()); fclose(f); }
    }

    signal(SIGTERM, signal_handler);
    signal(SIGINT, signal_handler);
    signal(SIGHUP, signal_handler);

    ps_device = zwp_primary_selection_device_manager_v1_get_device(
        ps_manager, wl_seat_obj);
    zwp_primary_selection_device_v1_add_listener(
        ps_device, &ps_device_listener, NULL);
    wl_display_roundtrip(wl_dpy);

    /* Create permanent 1x1 transparent surface.  Mutter/GNOME requires
       a mapped surface to deliver PRIMARY selection events.  The surface
       has an empty input region so it cannot steal keyboard focus. */
    if (create_daemon_surface() != 0) {
        fprintf(stderr, "Cannot create daemon surface\n");
        wayland_disconnect();
        return 1;
    }

    /* DETECTION ARCHITECTURE:
     * 1. Event-driven: compositor sends selection events when PRIMARY
     *    changes → ps_device_handle_selection fires → reads content
     *    and updates cache immediately.
     * 2. 50ms polling fallback: re-reads the current offer to catch
     *    content changes within the same selection (e.g. user extends
     *    a selection in the terminal).
     * 3. The permanent surface ensures Mutter delivers events without
     *    stealing focus (empty input region). */
    int wl_fd = wl_display_get_fd(wl_dpy);

    while (running) {
        while (wl_display_prepare_read(wl_dpy) != 0)
            wl_display_dispatch_pending(wl_dpy);

        if (wl_display_flush(wl_dpy) == -1 && errno != EAGAIN) {
            wl_display_cancel_read(wl_dpy);
            break;
        }

        struct pollfd pfd = { .fd = wl_fd, .events = POLLIN };
        int ret = poll(&pfd, 1, 50);

        if (ret < 0) {
            wl_display_cancel_read(wl_dpy);
            if (errno == EINTR) continue;
            break;
        }

        if (ret == 0) {
            wl_display_cancel_read(wl_dpy);
            /* Poll timeout — re-read current offer to detect changes */
            if (current_ps_offer && ps_has_text)
                check_and_update_primary();
            continue;
        }

        if (pfd.revents & POLLIN) {
            if (wl_display_read_events(wl_dpy) == -1) break;
            wl_display_dispatch_pending(wl_dpy);
        } else {
            wl_display_cancel_read(wl_dpy);
        }

        if (wl_display_get_error(wl_dpy) != 0) break;
    }

    wayland_disconnect();
    free(last_known_content);
    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);
    return 0;
}

/* ===== MAIN ======================================================= */

int main(int argc, char *argv[]) {
    const char *cache_dir_arg = NULL;

    enum { MODE_DAEMON, MODE_ONESHOT, MODE_GET_CLIP, MODE_COPY_CLIP,
           MODE_CLEAR_PRIMARY } mode = MODE_DAEMON;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--oneshot") == 0)
            mode = MODE_ONESHOT;
        else if (strcmp(argv[i], "--get-clipboard") == 0)
            mode = MODE_GET_CLIP;
        else if (strcmp(argv[i], "--copy-clipboard") == 0)
            mode = MODE_COPY_CLIP;
        else if (strcmp(argv[i], "--clear-primary") == 0)
            mode = MODE_CLEAR_PRIMARY;
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "Usage: %s [cache_dir] [--oneshot|--get-clipboard|"
                "--copy-clipboard|--clear-primary]\n\n"
                "Wayland selection monitor for zsh-edit-select\n\n"
                "Modes:\n"
                "  (default)         Daemon: monitor PRIMARY selection\n"
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

    switch (mode) {
        case MODE_ONESHOT:       return run_oneshot(cache_dir_arg);
        case MODE_GET_CLIP:      return run_get_clipboard();
        case MODE_COPY_CLIP:     return run_copy_clipboard();
        case MODE_CLEAR_PRIMARY: return run_clear_primary();
        case MODE_DAEMON:        return run_daemon(cache_dir_arg);
    }
    return 1;
}
