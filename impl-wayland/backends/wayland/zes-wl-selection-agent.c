// Copyright (c) 2025 Michael Matta
// Version: 0.6.4
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// Wayland clipboard integration agent for zsh-edit-select.
// Uses zwp_primary_selection_unstable_v1 for PRIMARY and wl_data_device for
// clipboard, completely replacing wl-clipboard (wl-paste / wl-copy) to
// eliminate process-spawn lag that causes typing delays.
//
// Build: make  (uses the Makefile in this directory)
//
// Modes:
//   zes-wl-selection-agent <cache_dir>         Daemon: sync clipboard state
//   zes-wl-selection-agent --oneshot            Print current PRIMARY and exit
//   zes-wl-selection-agent --get-clipboard      Print clipboard contents
//   zes-wl-selection-agent --copy-clipboard     Read stdin, set clipboard
//   zes-wl-selection-agent --clear-primary      Clear PRIMARY selection

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
#include "wlr-data-control-unstable-v1-client-protocol.h"
#include "ext-data-control-v1-client-protocol.h"

/* xdg-shell stable protocol — inline minimal definitions so we don't
   need an extra generated header just for the daemon surface. */
#include "xdg-shell-client-protocol.h"

/* Cache-directory layout constants and safety caps.
   CACHE_DIR_TEMPLATE: sprintf template for the HOME-based fallback path.
   PRIMARY_FILE / SEQ_FILE / PID_FILE: filenames inside the cache directory.
   MAX_SELECTION_SIZE: 1 MB cap on PRIMARY reads.
   MAX_CLIPBOARD_SIZE: 4 MB cap on clipboard reads (larger to accommodate
   rich pastes). */
#define CACHE_DIR_TEMPLATE "%s/.cache/zsh-edit-select"
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "agent.pid"
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
/* Monotonically increasing counter written to SEQ_FILE; the shell polls
   its mtime to detect selection changes without reading content. */
static unsigned long seq_counter = 0;
/* True when the current PRIMARY / clipboard offer advertises a text MIME. */
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
static struct wl_buffer *daemon_buffer = NULL;

/* Data-control protocol globals — used for Mechanism B (wlroots/KDE clipboard).
   Both protocols are structurally identical; prefer ext when both are available.
   dc_use_ext: true = using ext-data-control-v1, false = using zwlr variant. */
static struct zwlr_data_control_manager_v1 *wlr_dcm = NULL;
static struct ext_data_control_manager_v1 *ext_dcm = NULL;

/* Keyboard listener globals — used for Mechanism C (GNOME focus surface).
   keyboard_enter_serial: serial from the most recent wl_keyboard.enter event.
   keyboard_entered: set to true when the focus surface receives keyboard focus. */
static uint32_t keyboard_enter_serial = 0;
static bool keyboard_entered = false;

/* Data-control offer for clipboard — set by data-control device selection event.
   dc_clipboard_offer: opaque pointer to either zwlr_data_control_offer_v1 or
   ext_data_control_offer_v1 (cast as needed based on dc_use_ext flag).
   dc_clip_has_text: true when the current offer being built advertises text.
   dc_clip_has_text_sel: snapshot of dc_clip_has_text taken when the
   selection event fires — immune to later primary_selection data_offer
   events that would reset dc_clip_has_text for a different offer.
   dc_got_selection: true when the data-control device selection event fires. */
static void *dc_clipboard_offer = NULL;
static bool dc_clip_has_text = false;
static bool dc_clip_has_text_sel = false;
static bool dc_got_selection = false;
static bool dc_use_ext = false;

/* Set true whenever dd_handle_selection fires — even if the offer is NULL
   (empty clipboard).  Used as the exit condition for the focus-surface
   event loop in run_get_clipboard() so an empty clipboard does not hang. */
static bool got_clip_selection = false;

/* Mode flags — controls handler behavior */
static bool is_daemon_mode = false;
static bool got_selection = false; /* one-shot: set when selection event arrives */
/* Cached copy of the last PRIMARY content and its byte length.
   Used to skip redundant cache writes when content has not changed. */
static char *last_known_content = NULL;
static size_t last_known_len = 0;

/* For --copy-clipboard: data source serving */
static struct wl_data_source *copy_source = NULL;
static char *copy_data = NULL;
static size_t copy_data_len = 0;
static bool copy_done = false;

/* Persistent fds for write_primary() daemon hot path.
   Opened once after daemon() in run_daemon(); reused for all subsequent writes.
   -1 = not yet open (pre-daemon initial write uses the open/write/close fallback). */
static int fd_primary = -1;
static int fd_seq     = -1;

/* SIGTERM / SIGINT handler — sets the flag that exits all event loops. */
static void signal_handler(int sig) {
    (void)sig;
    running = 0;
}

/* Resolve cache directory path (from argument, XDG_RUNTIME_DIR, /dev/shm,
   or HOME), populate the four path globals (cache_dir, primary_path,
   seq_path, pid_path), and create the directory if needed.
   Returns 0 on success, -1 on failure. */
static int ensure_cache_dir(const char *dir) {
    if (dir && dir[0]) {
        snprintf(cache_dir, sizeof(cache_dir), "%s", dir);
    } else {
        const char *runtime = getenv("XDG_RUNTIME_DIR");
        if (runtime) {
            snprintf(cache_dir, sizeof(cache_dir), "%s/zsh-edit-select-%d",
                     runtime, (int)getuid());
        } else if (access("/dev/shm", W_OK | X_OK) == 0) {
            /* /dev/shm is guaranteed in-memory tmpfs on Linux — faster than
               HOME/.cache for short-lived modes without an explicit cache_dir.
               access() fails on non-Linux and the chain falls through cleanly. */
            snprintf(cache_dir, sizeof(cache_dir),
                     "/dev/shm/zsh-edit-select-%d", (int)getuid());
        } else {
            const char *home = getenv("HOME");
            if (!home) return -1;
            snprintf(cache_dir, sizeof(cache_dir), CACHE_DIR_TEMPLATE, home);
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

/* Write selection text to the PRIMARY cache file and the monotonic
   sequence number to the SEQ file.  Uses persistent fds when available
   (daemon hot path) or falls back to open/write/close (short-lived modes). */
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
        (void)!ftruncate(fd_primary, (off_t)len);

        /* primary must be fully committed before seq is touched —
           seq's mtime is the shell's only per-keypress detection signal. */
        char buf[24];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = pwrite(fd_seq, buf, (size_t)n, 0);
        (void)r;
        (void)!ftruncate(fd_seq, (off_t)n);
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

/* Helper: re-read the current PRIMARY offer, compare with cached content,
 * and update the cache files only if content actually changed.
 *
 * Called exclusively from the daemon's 50 ms poll-timeout path to detect
 * content changes within the same selection (e.g. the user extends a
 * terminal selection).  Selection-owner-change events are handled
 * separately in ps_device_handle_selection() which always writes.
 *
 * Skipping the write when content is unchanged saves 4 syscalls
 * (2 × pwrite + 2 × ftruncate) per poll cycle — ~80 syscalls/sec
 * while the selection is static. */
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
            /* Transfer ownership of the heap buffer from read_ps_offer()
               directly — avoids a redundant malloc+memcpy per event. */
            last_known_content = sel;
            last_known_len = len;
            sel = NULL;
        } else {
            last_known_content = NULL;
            last_known_len = 0;
        }
    }

    free(sel);
    return changed;
}

/* ------------------------------------------------------------------ */
/* Utility: read text from an fd with poll timeout                     */
/* ------------------------------------------------------------------ */
/* Read a bounded amount of data from fd with a poll-based timeout.
 * The fd is freshly created (pipe2), so O_NONBLOCK does not need to be
 * preserved across F_GETFL/F_SETFL — F_SETFL alone is sufficient.
 * The initial_timeout_ms is longer for the first chunk to cover the
 * round-trip to the selection owner; subsequent chunks use a shorter
 * 100 ms timeout to detect EOF quickly without burning CPU. */
static char *read_fd_with_timeout(int fd, size_t *out_len, size_t max_size,
                                   int initial_timeout_ms) {
    fcntl(fd, F_SETFL, O_NONBLOCK);

    char *buf = NULL;
    size_t total = 0, capacity = 0;
    struct pollfd pfd = { .fd = fd, .events = POLLIN };
    int timeout_ms = initial_timeout_ms;

    while (1) {
        int ret = poll(&pfd, 1, timeout_ms);
        if (ret < 0) { if (errno == EINTR) continue; break; }
        if (ret == 0) break;
        if ((pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) &&
            !(pfd.revents & POLLIN))
            break;

        if (pfd.revents & POLLIN) {
            if (total + 4096 > capacity) {
                capacity = capacity ? capacity * 2 : 4096;
                if (capacity > max_size) break;
                char *nb = realloc(buf, capacity + 1);
                if (!nb) { free(buf); buf = NULL; total = 0; break; }
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
/* Read text from a primary selection offer.
 * Creates a pipe, hands the write end to the compositor via receive(),
 * flushes the display to trigger delivery, then reads from the read end.
 * The write end is closed before reading so the read can detect EOF. */
static char *read_ps_offer(struct zwp_primary_selection_offer_v1 *offer,
                            size_t *out_len) {
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) == -1) return NULL;
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
/* Read text from a clipboard (wl_data_offer) offer.
 * Same pipe protocol as read_ps_offer but uses wl_data_offer_receive. */
static char *read_clip_offer(struct wl_data_offer *offer, size_t *out_len) {
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) == -1) return NULL;
    wl_data_offer_receive(offer, "text/plain;charset=utf-8", fds[1]);
    wl_display_flush(wl_dpy);
    close(fds[1]);
    char *data = read_fd_with_timeout(fds[0], out_len, MAX_CLIPBOARD_SIZE, 500);
    close(fds[0]);
    return data;
}

/* ===== BASE64 LOOKUP TABLE ======================================== */

static const char b64_enc_table[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* ===== OSC 52 WRITE (Mechanism A) ================================= */
/* OSC 52 read is intentionally omitted: it requires putting the terminal
   in raw mode and triggers a security confirmation popup on Kitty
   ("A program wants to read from the system clipboard").  The three
   Wayland-native mechanisms (wl_data_device, data-control, focus surface)
   cover all major compositors without touching the terminal. */

/* Write clipboard data to the terminal via OSC 52 escape sequence.
 * Single write() syscall to /dev/tty — no Wayland involvement.
 * Returns true if the write succeeded (terminal accepted the sequence). */
static bool osc52_write(const char *data, size_t len) {
    int tty_fd = open("/dev/tty", O_WRONLY | O_CLOEXEC);
    if (tty_fd < 0) return false;

    /* Encode base64 directly into the framing buffer to avoid a
       separate malloc/free/strlen for the intermediate b64 string.
       Layout: "\e]52;c;" (7) + base64 (b64_len) + BEL (1) */
    size_t b64_len = 4 * ((len + 2) / 3);
    size_t total = 7 + b64_len + 1;
    char *buf = malloc(total);
    if (!buf) { close(tty_fd); return false; }

    memcpy(buf, "\033]52;c;", 7);

    /* Inline base64 encode into buf+7 */
    {
        const unsigned char *src = (const unsigned char *)data;
        size_t i = 0, j = 7;
        while (i < len) {
            uint32_t a = (i < len) ? src[i++] : 0;
            uint32_t b = (i < len) ? src[i++] : 0;
            uint32_t c = (i < len) ? src[i++] : 0;
            uint32_t triple = (a << 16) | (b << 8) | c;
            buf[j++] = b64_enc_table[(triple >> 18) & 0x3F];
            buf[j++] = b64_enc_table[(triple >> 12) & 0x3F];
            buf[j++] = b64_enc_table[(triple >> 6) & 0x3F];
            buf[j++] = b64_enc_table[triple & 0x3F];
        }
        /* RFC 4648 padding */
        if (len % 3 >= 1) buf[j - 1] = '=';
        if (len % 3 == 1) buf[j - 2] = '=';
    }
    buf[7 + b64_len] = '\a';

    size_t written = 0;
    while (written < total) {
        ssize_t r = write(tty_fd, buf + written, total - written);
        if (r > 0) { written += r; continue; }
        if (r < 0 && errno == EINTR) continue;
        break;
    }
    free(buf);
    close(tty_fd);
    return written == total;
}

/* ===== DATA-CONTROL PROTOCOL LISTENERS (Mechanism B) ============== */

/* Offer listener — tracks whether the data-control offer has text MIME. */
static void dc_offer_handle_offer_wlr(void *data,
        struct zwlr_data_control_offer_v1 *offer, const char *mime_type) {
    (void)data; (void)offer;
    if (strcmp(mime_type, "text/plain;charset=utf-8") == 0 ||
        strcmp(mime_type, "text/plain") == 0)
        dc_clip_has_text = true;
}

static const struct zwlr_data_control_offer_v1_listener dc_offer_listener_wlr = {
    .offer = dc_offer_handle_offer_wlr,
};

static void dc_offer_handle_offer_ext(void *data,
        struct ext_data_control_offer_v1 *offer, const char *mime_type) {
    (void)data; (void)offer;
    if (strcmp(mime_type, "text/plain;charset=utf-8") == 0 ||
        strcmp(mime_type, "text/plain") == 0)
        dc_clip_has_text = true;
}

static const struct ext_data_control_offer_v1_listener dc_offer_listener_ext = {
    .offer = dc_offer_handle_offer_ext,
};

/* Device listeners — handle data_offer, selection, finished, primary_selection */

/* wlr variant */
static void dc_device_data_offer_wlr(void *data,
        struct zwlr_data_control_device_v1 *dev,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    dc_clip_has_text = false;
    zwlr_data_control_offer_v1_add_listener(offer, &dc_offer_listener_wlr, NULL);
}

static void dc_device_selection_wlr(void *data,
        struct zwlr_data_control_device_v1 *dev,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    if (dc_clipboard_offer && dc_clipboard_offer != offer)
        zwlr_data_control_offer_v1_destroy(dc_clipboard_offer);
    dc_clipboard_offer = offer;
    dc_clip_has_text_sel = dc_clip_has_text;
    dc_got_selection = true;
}

static void dc_device_finished_wlr(void *data,
        struct zwlr_data_control_device_v1 *dev) {
    (void)data; (void)dev;
}

static void dc_device_primary_selection_wlr(void *data,
        struct zwlr_data_control_device_v1 *dev,
        struct zwlr_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    /* PRIMARY is handled by zwp_primary_selection — destroy the offer
       to avoid leaking the proxy object. */
    if (offer) zwlr_data_control_offer_v1_destroy(offer);
}

static const struct zwlr_data_control_device_v1_listener dc_device_listener_wlr = {
    .data_offer        = dc_device_data_offer_wlr,
    .selection         = dc_device_selection_wlr,
    .finished          = dc_device_finished_wlr,
    .primary_selection = dc_device_primary_selection_wlr,
};

/* ext variant */
static void dc_device_data_offer_ext(void *data,
        struct ext_data_control_device_v1 *dev,
        struct ext_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    dc_clip_has_text = false;
    ext_data_control_offer_v1_add_listener(offer, &dc_offer_listener_ext, NULL);
}

static void dc_device_selection_ext(void *data,
        struct ext_data_control_device_v1 *dev,
        struct ext_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    if (dc_clipboard_offer && dc_clipboard_offer != offer)
        ext_data_control_offer_v1_destroy(dc_clipboard_offer);
    dc_clipboard_offer = offer;
    dc_clip_has_text_sel = dc_clip_has_text;
    dc_got_selection = true;
}

static void dc_device_finished_ext(void *data,
        struct ext_data_control_device_v1 *dev) {
    (void)data; (void)dev;
}

static void dc_device_primary_selection_ext(void *data,
        struct ext_data_control_device_v1 *dev,
        struct ext_data_control_offer_v1 *offer) {
    (void)data; (void)dev;
    /* PRIMARY is handled by zwp_primary_selection — destroy the offer
       to avoid leaking the proxy object. */
    if (offer) ext_data_control_offer_v1_destroy(offer);
}

static const struct ext_data_control_device_v1_listener dc_device_listener_ext = {
    .data_offer        = dc_device_data_offer_ext,
    .selection         = dc_device_selection_ext,
    .finished          = dc_device_finished_ext,
    .primary_selection = dc_device_primary_selection_ext,
};

/* Read text from a data-control clipboard offer (either wlr or ext).
 * Same pipe protocol as read_clip_offer(). */
static char *read_dc_clip_offer(size_t *out_len) {
    if (!dc_clipboard_offer || !dc_clip_has_text_sel) {
        *out_len = 0;
        return NULL;
    }
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) == -1) return NULL;
    if (dc_use_ext)
        ext_data_control_offer_v1_receive(dc_clipboard_offer,
            "text/plain;charset=utf-8", fds[1]);
    else
        zwlr_data_control_offer_v1_receive(dc_clipboard_offer,
            "text/plain;charset=utf-8", fds[1]);
    wl_display_flush(wl_dpy);
    close(fds[1]);
    char *data = read_fd_with_timeout(fds[0], out_len, MAX_CLIPBOARD_SIZE, 500);
    close(fds[0]);
    return data;
}

/* Data-control source listeners for --copy-clipboard (Mechanism B). */

static void dc_source_send_wlr(void *data,
        struct zwlr_data_control_source_v1 *src,
        const char *mime_type, int32_t fd) {
    (void)data; (void)src; (void)mime_type;
    if (copy_data && copy_data_len > 0) {
        size_t written = 0;
        while (written < copy_data_len) {
            ssize_t n = write(fd, copy_data + written, copy_data_len - written);
            if (n > 0) { written += n; continue; }
            if (n < 0 && errno == EINTR) continue;
            break;
        }
    }
    close(fd);
}

static void dc_source_cancelled_wlr(void *data,
        struct zwlr_data_control_source_v1 *src) {
    (void)data;
    zwlr_data_control_source_v1_destroy(src);
    copy_done = true;
}

static const struct zwlr_data_control_source_v1_listener dc_source_listener_wlr = {
    .send      = dc_source_send_wlr,
    .cancelled = dc_source_cancelled_wlr,
};

static void dc_source_send_ext(void *data,
        struct ext_data_control_source_v1 *src,
        const char *mime_type, int32_t fd) {
    (void)data; (void)src; (void)mime_type;
    if (copy_data && copy_data_len > 0) {
        size_t written = 0;
        while (written < copy_data_len) {
            ssize_t n = write(fd, copy_data + written, copy_data_len - written);
            if (n > 0) { written += n; continue; }
            if (n < 0 && errno == EINTR) continue;
            break;
        }
    }
    close(fd);
}

static void dc_source_cancelled_ext(void *data,
        struct ext_data_control_source_v1 *src) {
    (void)data;
    ext_data_control_source_v1_destroy(src);
    copy_done = true;
}

static const struct ext_data_control_source_v1_listener dc_source_listener_ext = {
    .send      = dc_source_send_ext,
    .cancelled = dc_source_cancelled_ext,
};

/* ===== KEYBOARD LISTENER (Mechanism C) ============================ */

static void keyboard_handle_keymap(void *data, struct wl_keyboard *kb,
                                    uint32_t format, int32_t fd, uint32_t size) {
    (void)data; (void)kb; (void)format; (void)size;
    close(fd);
}

static void keyboard_handle_enter(void *data, struct wl_keyboard *kb,
                                   uint32_t serial, struct wl_surface *surface,
                                   struct wl_array *keys) {
    (void)data; (void)kb; (void)surface; (void)keys;
    keyboard_enter_serial = serial;
    keyboard_entered = true;
}

static void keyboard_handle_leave(void *data, struct wl_keyboard *kb,
                                   uint32_t serial, struct wl_surface *surface) {
    (void)data; (void)kb; (void)serial; (void)surface;
}

static void keyboard_handle_key(void *data, struct wl_keyboard *kb,
                                 uint32_t serial, uint32_t time,
                                 uint32_t key, uint32_t state) {
    (void)data; (void)kb; (void)serial; (void)time; (void)key; (void)state;
}

static void keyboard_handle_modifiers(void *data, struct wl_keyboard *kb,
                                       uint32_t serial, uint32_t depressed,
                                       uint32_t latched, uint32_t locked,
                                       uint32_t group) {
    (void)data; (void)kb; (void)serial; (void)depressed;
    (void)latched; (void)locked; (void)group;
}

static void keyboard_handle_repeat_info(void *data, struct wl_keyboard *kb,
                                         int32_t rate, int32_t delay) {
    (void)data; (void)kb; (void)rate; (void)delay;
}

static const struct wl_keyboard_listener keyboard_listener = {
    .keymap      = keyboard_handle_keymap,
    .enter       = keyboard_handle_enter,
    .leave       = keyboard_handle_leave,
    .key         = keyboard_handle_key,
    .modifiers   = keyboard_handle_modifiers,
    .repeat_info = keyboard_handle_repeat_info,
};

/* ===== PRIMARY SELECTION LISTENERS ================================ */

/* Called once per MIME type advertised by the selection owner.
 * Multiple type aliases for plain text exist across GUI toolkits;
 * accepting any of them ensures compatibilty with terminals, browsers,
 * and legacy X11 applications running via XWayland. */
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

/* Listener table for individual PRIMARY selection offers.  One instance
   is shared across all offers — the offer pointer itself is the state. */
static const struct zwp_primary_selection_offer_v1_listener ps_offer_listener = {
    .offer = ps_offer_handle_offer,
};

static void ps_device_handle_data_offer(void *data,
        struct zwp_primary_selection_device_v1 *dev,
        struct zwp_primary_selection_offer_v1 *offer) {
    (void)data; (void)dev;
    /* Reset ps_has_text before adding the listener: the new offer
       advertises its types via subsequent ps_offer_handle_offer calls,
       so any leftover state from the previous offer must be cleared first. */
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
            /* Transfer ownership — avoids redundant malloc+memcpy. */
            last_known_content = sel;
            last_known_len = len;
            sel = NULL;
        } else {
            last_known_content = NULL;
            last_known_len = 0;
        }
    }

    free(sel);
}

/* Listener table for the PRIMARY selection device.
   data_offer fires first (once per advertised MIME type) then selection
   fires to announce the active offer — both are required for correct
   text detection. */
static const struct zwp_primary_selection_device_v1_listener ps_device_listener = {
    .data_offer = ps_device_handle_data_offer,
    .selection = ps_device_handle_selection,
};

/* ===== CLIPBOARD (wl_data_device) LISTENERS ======================= */

/* Mirror of ps_offer_handle_offer for clipboard offers.
 * Clipboard applications tend to advertise both UTF-8 and plain text;
 * matching either is sufficient — we always request text/plain;charset=utf-8
 * from read_clip_offer() regardless of which type triggered the flag. */
static void clip_offer_handle_offer(void *data, struct wl_data_offer *offer,
                                     const char *mime_type) {
    (void)data; (void)offer;
    if (strcmp(mime_type, "text/plain;charset=utf-8") == 0 ||
        strcmp(mime_type, "text/plain") == 0)
        clip_has_text = true;
}

/* Listener for clipboard (wl_data_offer) type advertisements. */
static const struct wl_data_offer_listener clip_offer_listener = {
    .offer = clip_offer_handle_offer,
};

static void dd_handle_data_offer(void *data, struct wl_data_device *dev,
                                  struct wl_data_offer *offer) {
    (void)data; (void)dev;
    /* Reset clip_has_text: the new clipboard offer will populate it via
       the clip_offer_listener below before dd_handle_selection fires. */
    clip_has_text = false;
    wl_data_offer_add_listener(offer, &clip_offer_listener, NULL);
}

/* The enter/leave/motion/drop events are mandatory members of the
   wl_data_device_listener interface but are not relevant to clipboard
   monitoring — drag-and-drop is not used by this agent. */
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
    /* Destroy the previous offer before replacing it to avoid resource leaks.
       The compositor owns the offer object, but the client must destroy it
       when it is no longer needed. */
    if (current_clipboard_offer && current_clipboard_offer != offer)
        wl_data_offer_destroy(current_clipboard_offer);
    current_clipboard_offer = offer;
    got_clip_selection = true;
}

/* Listener for the wl_data_device (clipboard).  All drag-and-drop
   callbacks are no-ops; only data_offer and selection are used. */
static const struct wl_data_device_listener dd_listener = {
    .data_offer = dd_handle_data_offer,
    .enter      = dd_handle_enter,
    .leave      = dd_handle_leave,
    .motion     = dd_handle_motion,
    .drop       = dd_handle_drop,
    .selection  = dd_handle_selection,
};

/* ===== DATA SOURCE (for --copy-clipboard) ========================= */

/* wl_data_source::target callback.  Notifies which MIME type the paste
   requestor chose; unused — we always send the same UTF-8 text. */
static void ds_handle_target(void *data, struct wl_data_source *src,
                              const char *mime_type) {
    (void)data;(void)src;(void)mime_type;
}

/* ds_handle_send: called by the compositor when a paste is requested.
 * Writes the buffered clipboard data to the fd provided by the compositor,
 * then closes it.  The write loop handles short writes on large buffers. */
static void ds_handle_send(void *data, struct wl_data_source *src,
                            const char *mime_type, int32_t fd) {
    (void)data; (void)src; (void)mime_type;
    if (copy_data && copy_data_len > 0) {
        size_t written = 0;
        while (written < copy_data_len) {
            ssize_t n = write(fd, copy_data + written, copy_data_len - written);
            if (n > 0) { written += n; continue; }
            if (n < 0 && errno == EINTR) continue;
            break;
        }
    }
    close(fd);
}

/* ds_handle_cancelled: another application became the clipboard owner.
 * Destroy the source object and signal the serve loop to exit. */
static void ds_handle_cancelled(void *data, struct wl_data_source *src) {
    (void)data;
    wl_data_source_destroy(src);
    copy_source = NULL;
    copy_done = true;
}

/* Listener for the wl_data_source used by --copy-clipboard.
   Only target, send, and cancelled are relevant — action callbacks
   (set_actions / action) are not needed for plain clipboard copy. */
static const struct wl_data_source_listener ds_listener = {
    .target    = ds_handle_target,
    .send      = ds_handle_send,
    .cancelled = ds_handle_cancelled,
};

/* ===== XDG-SHELL / SURFACE LISTENERS ============================== */

static void xdg_wm_base_ping(void *data, struct xdg_wm_base *base,
                              uint32_t serial) {
    (void)data;
    /* The compositor sends pings to verify the client is still responsive.
       Failure to respond with pong within the compositor's timeout causes
       the client to be marked as unresponsive — some compositors then
       stop delivering events. */
    xdg_wm_base_pong(base, serial);
}

/* Listener for xdg_wm_base — only ping is interesting for this daemon. */
static const struct xdg_wm_base_listener xdg_wm_base_listener = {
    .ping = xdg_wm_base_ping,
};

static void xdg_surface_handle_configure(void *data,
        struct xdg_surface *surface, uint32_t serial) {
    (void)data;
    /* Acknowledging configure is mandatory before attaching a buffer;
       without it the compositor considers the surface to be in an
       inconsistent state and will not map it. */
    xdg_surface_ack_configure(surface, serial);
}

/* Listener for the xdg_surface of the daemon window.  configure must be
   acknowledged before a buffer can be attached; see xdg_surface_handle_configure. */
static const struct xdg_surface_listener xdg_surface_listener = {
    .configure = xdg_surface_handle_configure,
};

/* xdg_toplevel::configure — handle compositor-requested size/state changes.
   The daemon surface is always 1x1 and never resizes; size hints from the
   compositor are intentionally ignored.  The configure event itself must
   still be consumed to keep the message queue from growing. */
static void xdg_toplevel_handle_configure(void *data,
        struct xdg_toplevel *toplevel, int32_t w, int32_t h,
        struct wl_array *states) {
    (void)data;(void)toplevel;(void)w;(void)h;(void)states;
}

/* xdg_toplevel::close — compositor requests the surface to close
   (e.g. task-manager kill).  Signals the daemon to shut down. */
static void xdg_toplevel_handle_close(void *data,
        struct xdg_toplevel *toplevel) {
    (void)data;(void)toplevel;
    running = 0;
}

/* Listener for the daemon toplevel.  configure is a no-op (fixed 1x1);
   close signals shutdown so the daemon exits cleanly on task-manager kill. */
static const struct xdg_toplevel_listener xdg_toplevel_listener = {
    .configure = xdg_toplevel_handle_configure,
    .close     = xdg_toplevel_handle_close,
};

/* ===== REGISTRY =================================================== */

/* Bind Wayland globals as they are advertised.
 * Version caps are applied to avoid using features not yet supported:
 * wl_compositor capped at 4 (damage_buffer, preferred_buffer_scale),
 * wl_data_device_manager capped at 3 (wl_surface.set_selection).
 * Data-control protocols: prefer ext-data-control-v1 over wlr when both
 * are advertised (ext is the standardized successor). */
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
    } else if (strcmp(interface, "ext_data_control_manager_v1") == 0) {
        ext_dcm = wl_registry_bind(reg, name,
            &ext_data_control_manager_v1_interface, 1);
    } else if (strcmp(interface, "zwlr_data_control_manager_v1") == 0) {
        wlr_dcm = wl_registry_bind(reg, name,
            &zwlr_data_control_manager_v1_interface,
            version < 2 ? version : 2);
    }
}

/* wl_registry::global_remove — required by the listener interface.
   No-op because this agent does not handle hot-unplug of globals. */
static void registry_handle_global_remove(void *data, struct wl_registry *reg,
                                           uint32_t name) {
    (void)data;(void)reg;(void)name;
}

/* Registry listener — discovers globals at startup via global callbacks
   and ignores subsequent hot-plug events via the no-op global_remove. */
static const struct wl_registry_listener registry_listener = {
    .global = registry_handle_global,
    .global_remove = registry_handle_global_remove,
};

/* ===== HELPERS ==================================================== */

/* Open the Wayland display connection and trigger the first registry
 * roundtrip to populate all global object pointers before any mode
 * function is called. */
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

/* Release all Wayland objects in reverse dependency order.
 * Each object must be destroyed before the objects it depends on;
 * failing to destroy in order may cause compositor-side protocol errors. */
static void wayland_disconnect(void) {
    if (current_ps_offer) {
        zwp_primary_selection_offer_v1_destroy(current_ps_offer);
        current_ps_offer = NULL;
    }
    if (current_clipboard_offer) {
        wl_data_offer_destroy(current_clipboard_offer);
        current_clipboard_offer = NULL;
    }
    if (copy_source) {
        wl_data_source_destroy(copy_source);
        copy_source = NULL;
    }
    /* Data-control offer cleanup */
    if (dc_clipboard_offer) {
        if (dc_use_ext)
            ext_data_control_offer_v1_destroy(dc_clipboard_offer);
        else
            zwlr_data_control_offer_v1_destroy(dc_clipboard_offer);
        dc_clipboard_offer = NULL;
    }
    if (ps_device) {
        zwp_primary_selection_device_v1_destroy(ps_device);
        ps_device = NULL;
    }
    if (ps_manager) {
        zwp_primary_selection_device_manager_v1_destroy(ps_manager);
        ps_manager = NULL;
    }
    /* Data-control manager cleanup */
    if (ext_dcm) { ext_data_control_manager_v1_destroy(ext_dcm); ext_dcm = NULL; }
    if (wlr_dcm) { zwlr_data_control_manager_v1_destroy(wlr_dcm); wlr_dcm = NULL; }
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

/* Forward declarations */
static int create_daemon_surface(void);
static int create_focus_surface(struct wl_surface **out_surface,
                                 struct xdg_surface **out_xdg_surface,
                                 struct xdg_toplevel **out_xdg_toplevel,
                                 struct wl_buffer **out_buffer);

/* ===== FOCUS SURFACE (Mechanism C) ================================ */

/* Create a 1×1 xdg_toplevel surface that CAN receive keyboard focus.
 * Unlike create_daemon_surface() which sets an empty input region to prevent
 * focus stealing, this surface allows input so that the compositor (especially
 * Mutter/GNOME) delivers keyboard.enter events with a valid serial.
 * The surface is intended to be short-lived and destroyed immediately after
 * the needed event (keyboard focus or clipboard offer) is received.
 *
 * Returns 0 on success.  Outputs are set to the created objects so the caller
 * can destroy them after use. */
static int create_focus_surface(struct wl_surface **out_surface,
                                 struct xdg_surface **out_xdg_surface,
                                 struct xdg_toplevel **out_xdg_toplevel,
                                 struct wl_buffer **out_buffer) {
    if (!wl_comp || !xdg_wmbase || !wl_shm_obj) return -1;

    /* Create 1x1 pixel SHM buffer (fully transparent ARGB) */
    int stride = 4, size = stride;
    int shm_fd = -1;
#ifdef __linux__
    shm_fd = memfd_create("zes-focus-buf", MFD_CLOEXEC);
#endif
    if (shm_fd < 0) {
        char name[] = "/zes-focus-XXXXXX";
        shm_fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (shm_fd >= 0) shm_unlink(name);
    }
    if (shm_fd < 0) return -1;
    if (ftruncate(shm_fd, size) < 0) { close(shm_fd); return -1; }
    struct wl_shm_pool *pool = wl_shm_create_pool(wl_shm_obj, shm_fd, size);
    *out_buffer = wl_shm_pool_create_buffer(
        pool, 0, 1, 1, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(shm_fd);
    if (!*out_buffer) return -1;

    *out_surface = wl_compositor_create_surface(wl_comp);
    if (!*out_surface) {
        wl_buffer_destroy(*out_buffer);
        *out_buffer = NULL;
        return -1;
    }

    /* NO empty input region — this surface must accept keyboard focus
       so Mutter delivers clipboard events and keyboard.enter serial. */

    *out_xdg_surface = xdg_wm_base_get_xdg_surface(xdg_wmbase, *out_surface);
    xdg_surface_add_listener(*out_xdg_surface, &xdg_surface_listener, NULL);

    *out_xdg_toplevel = xdg_surface_get_toplevel(*out_xdg_surface);
    xdg_toplevel_add_listener(*out_xdg_toplevel, &xdg_toplevel_listener, NULL);

    /* Initial commit to trigger the configure sequence */
    wl_surface_commit(*out_surface);
    wl_display_roundtrip(wl_dpy);

    /* Attach 1x1 transparent pixel — maps the surface */
    wl_surface_attach(*out_surface, *out_buffer, 0, 0);
    wl_surface_damage(*out_surface, 0, 0, 1, 1);
    wl_surface_commit(*out_surface);
    wl_display_roundtrip(wl_dpy);

    return 0;
}

/* Destroy focus surface and its associated objects. */
static void destroy_focus_surface(struct wl_surface *surface,
                                   struct xdg_surface *xdg_surf,
                                   struct xdg_toplevel *toplevel,
                                   struct wl_buffer *buffer) {
    if (toplevel)  xdg_toplevel_destroy(toplevel);
    if (xdg_surf)  xdg_surface_destroy(xdg_surf);
    if (surface)   wl_surface_destroy(surface);
    if (buffer)    wl_buffer_destroy(buffer);
}

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
            /* Update cache so daemon-based detection stays in sync on
               Mutter, where focus gating prevents the daemon from receiving
               PRIMARY events directly. */
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

/* Print clipboard text to stdout and exit.
 * Three mechanisms attempted — devices are bound in a single batch
 * before one shared roundtrip to minimise Wayland IPC latency:
 *   1. wl_data_device + data-control (batched roundtrip)
 *   2. Focus surface (Mechanism C) — GNOME < 47 fallback */
static int run_get_clipboard(void) {
    if (wayland_connect() != 0) return 1;
    if (!wl_seat_obj) {
        wayland_disconnect();
        return 1;
    }

    char *data = NULL;
    size_t len = 0;

    /* --- Batch-bind both device types before a single roundtrip --- */
    struct ext_data_control_device_v1 *ext_dc_dev = NULL;
    struct zwlr_data_control_device_v1 *wlr_dc_dev = NULL;

    if (wl_ddm) {
        wl_dd = wl_data_device_manager_get_data_device(wl_ddm, wl_seat_obj);
        wl_data_device_add_listener(wl_dd, &dd_listener, NULL);
    }
    if (ext_dcm) {
        dc_use_ext = true;
        dc_clipboard_offer = NULL;
        dc_clip_has_text = false;
        dc_clip_has_text_sel = false;
        dc_got_selection = false;
        ext_dc_dev = ext_data_control_manager_v1_get_data_device(
            ext_dcm, wl_seat_obj);
        ext_data_control_device_v1_add_listener(ext_dc_dev,
            &dc_device_listener_ext, NULL);
    } else if (wlr_dcm) {
        dc_use_ext = false;
        dc_clipboard_offer = NULL;
        dc_clip_has_text = false;
        dc_clip_has_text_sel = false;
        dc_got_selection = false;
        wlr_dc_dev = zwlr_data_control_manager_v1_get_data_device(
            wlr_dcm, wl_seat_obj);
        zwlr_data_control_device_v1_add_listener(wlr_dc_dev,
            &dc_device_listener_wlr, NULL);
    }

    /* Single roundtrip processes events from all bound devices. */
    wl_display_roundtrip(wl_dpy);

    /* Check wl_data_device result first (cheapest path). */
    if (current_clipboard_offer && clip_has_text) {
        data = read_clip_offer(current_clipboard_offer, &len);
        if (data && len > 0) {
            fwrite(data, 1, len, stdout);
            free(data);
            if (ext_dc_dev) ext_data_control_device_v1_destroy(ext_dc_dev);
            if (wlr_dc_dev) zwlr_data_control_device_v1_destroy(wlr_dc_dev);
            wayland_disconnect();
            return 0;
        }
        free(data);
        data = NULL;
    }

    /* Check data-control result (works on wlroots/KDE/GNOME 47+). */
    if (dc_clipboard_offer && dc_clip_has_text_sel) {
        data = read_dc_clip_offer(&len);
        if (data && len > 0) {
            fwrite(data, 1, len, stdout);
            free(data);
            if (ext_dc_dev) ext_data_control_device_v1_destroy(ext_dc_dev);
            if (wlr_dc_dev) zwlr_data_control_device_v1_destroy(wlr_dc_dev);
            wayland_disconnect();
            return 0;
        }
        free(data);
        data = NULL;
    }

    /* Clean up data-control devices before the focus-surface fallback. */
    if (ext_dc_dev) { ext_data_control_device_v1_destroy(ext_dc_dev); ext_dc_dev = NULL; }
    if (wlr_dc_dev) { zwlr_data_control_device_v1_destroy(wlr_dc_dev); wlr_dc_dev = NULL; }

    /* Focus surface fallback (Mechanism C) — GNOME < 47
     * Create a surface that CAN receive keyboard focus so the compositor
     * delivers wl_data_device.selection events.  The loop exits on
     * got_clip_selection (set by dd_handle_selection) rather than on
     * current_clipboard_offer, so an empty clipboard exits immediately
     * instead of hanging forever. */
    if (wl_comp && xdg_wmbase && wl_shm_obj && wl_ddm) {
        struct wl_surface *focus_surf = NULL;
        struct xdg_surface *focus_xdg_surf = NULL;
        struct xdg_toplevel *focus_toplevel = NULL;
        struct wl_buffer *focus_buffer = NULL;

        /* Ensure wl_data_device is bound */
        if (!wl_dd) {
            wl_dd = wl_data_device_manager_get_data_device(wl_ddm, wl_seat_obj);
            wl_data_device_add_listener(wl_dd, &dd_listener, NULL);
        }

        /* Reset clipboard offer state */
        if (current_clipboard_offer) {
            wl_data_offer_destroy(current_clipboard_offer);
            current_clipboard_offer = NULL;
        }
        clip_has_text = false;
        got_clip_selection = false;

        if (create_focus_surface(&focus_surf, &focus_xdg_surf,
                                  &focus_toplevel, &focus_buffer) == 0) {
            /* Event-driven loop: block until the selection event fires.
             * dd_handle_selection sets got_clip_selection for both
             * non-NULL and NULL offers, preventing infinite hang on
             * empty clipboard.  Timeout: 50 × 100 ms = 5 seconds. */
            int wl_fd = wl_display_get_fd(wl_dpy);
            int timeout_count = 0;
            while (!got_clip_selection && timeout_count < 50) {
                while (wl_display_prepare_read(wl_dpy) != 0)
                    wl_display_dispatch_pending(wl_dpy);
                wl_display_flush(wl_dpy);
                struct pollfd pfd = { .fd = wl_fd, .events = POLLIN };
                int ret = poll(&pfd, 1, 100);
                if (ret < 0) {
                    wl_display_cancel_read(wl_dpy);
                    if (errno == EINTR) continue;
                    break;
                }
                if (ret == 0) {
                    wl_display_cancel_read(wl_dpy);
                    timeout_count++;
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

            if (current_clipboard_offer && clip_has_text) {
                data = read_clip_offer(current_clipboard_offer, &len);
                if (data && len > 0)
                    fwrite(data, 1, len, stdout);
                free(data);
            }

            destroy_focus_surface(focus_surf, focus_xdg_surf,
                                   focus_toplevel, focus_buffer);
        }
    }

    wayland_disconnect();
    return 0;
}

/* ===== MODE: --copy-clipboard ===================================== */

/* read_all_stdin: drain stdin into a malloc'd buffer and return it.
 * The buffer is grown exponentially; capped by MAX_CLIPBOARD_SIZE. */
static char *read_all_stdin(size_t *out_len) {
    size_t capacity = 4096, total = 0;
    char *buf = malloc(capacity);
    if (!buf) return NULL;

    while (1) {
        if (total + 4096 > capacity) {
            capacity *= 2;
            if (capacity > MAX_CLIPBOARD_SIZE) break;
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

/* Take ownership of the Wayland clipboard and serve paste requests.
 * Three mechanisms attempted in order:
 *   1. OSC 52 write to /dev/tty — fire-and-forget; single write()
 *   2. Data-control set_selection (Mechanism B) — wlroots/KDE; no serial
 *   3. Focus surface + wl_keyboard serial / serial=0 (Mechanism C)
 *
 * Steps 1 and 2 are not mutually exclusive — both run. OSC 52 sets it for
 * the terminal; data-control sets it at the compositor level for GUI apps.
 * When data-control succeeds, the wl_data_device path is skipped entirely
 * to avoid creating redundant protocol objects and a source-cancellation
 * race between the two clipboard sources.
 *
 * Forks immediately so the shell is not blocked: the parent exits at
 * once; the child runs a background event loop alive until some other
 * client calls set_selection (signalled via cancelled callback) or the
 * process is sent SIGTERM. */
static int run_copy_clipboard(void) {
    copy_data = read_all_stdin(&copy_data_len);
    if (!copy_data || copy_data_len == 0) {
        free(copy_data);
        return 1;
    }

    /* Step 1: OSC 52 write — fire-and-forget; single write(); no waiting */
    osc52_write(copy_data, copy_data_len);

    if (wayland_connect() != 0) { free(copy_data); return 1; }
    if (!wl_seat_obj) {
        free(copy_data); wayland_disconnect(); return 1;
    }

    /* Step 2: Data-control set_selection (Mechanism B) — no serial needed.
     * Creates a data-control source that the child will serve. */
    bool dc_copy_done = false;
    if (ext_dcm || wlr_dcm) {
        if (ext_dcm) {
            dc_use_ext = true;
            struct ext_data_control_device_v1 *dc_dev =
                ext_data_control_manager_v1_get_data_device(ext_dcm, wl_seat_obj);
            struct ext_data_control_source_v1 *dc_src =
                ext_data_control_manager_v1_create_data_source(ext_dcm);
            ext_data_control_source_v1_offer(dc_src, "text/plain;charset=utf-8");
            ext_data_control_source_v1_offer(dc_src, "text/plain");
            ext_data_control_source_v1_offer(dc_src, "UTF8_STRING");
            ext_data_control_source_v1_offer(dc_src, "STRING");
            ext_data_control_source_v1_add_listener(dc_src,
                &dc_source_listener_ext, NULL);
            ext_data_control_device_v1_set_selection(dc_dev, dc_src);
            wl_display_flush(wl_dpy);
            dc_copy_done = true;
        } else {
            dc_use_ext = false;
            struct zwlr_data_control_device_v1 *dc_dev =
                zwlr_data_control_manager_v1_get_data_device(wlr_dcm, wl_seat_obj);
            struct zwlr_data_control_source_v1 *dc_src =
                zwlr_data_control_manager_v1_create_data_source(wlr_dcm);
            zwlr_data_control_source_v1_offer(dc_src, "text/plain;charset=utf-8");
            zwlr_data_control_source_v1_offer(dc_src, "text/plain");
            zwlr_data_control_source_v1_offer(dc_src, "UTF8_STRING");
            zwlr_data_control_source_v1_offer(dc_src, "STRING");
            zwlr_data_control_source_v1_add_listener(dc_src,
                &dc_source_listener_wlr, NULL);
            zwlr_data_control_device_v1_set_selection(dc_dev, dc_src);
            wl_display_flush(wl_dpy);
            dc_copy_done = true;
        }
    }

    /* Step 3: wl_data_device path — only when data-control is unavailable.
     * On compositors without data-control (GNOME < 47) we must acquire
     * keyboard focus to obtain a valid serial for wl_data_device.set_selection.
     * When data-control succeeded, skip this entirely to avoid creating
     * redundant protocol objects and a cancellation race between the two
     * clipboard sources. */
    if (!dc_copy_done && wl_ddm) {
        wl_dd = wl_data_device_manager_get_data_device(wl_ddm, wl_seat_obj);
        wl_data_device_add_listener(wl_dd, &dd_listener, NULL);

        copy_source = wl_data_device_manager_create_data_source(wl_ddm);
        wl_data_source_offer(copy_source, "text/plain;charset=utf-8");
        wl_data_source_offer(copy_source, "text/plain");
        wl_data_source_offer(copy_source, "UTF8_STRING");
        wl_data_source_offer(copy_source, "STRING");
        wl_data_source_add_listener(copy_source, &ds_listener, NULL);

        /* GNOME fallback — acquire keyboard focus for a valid serial. */
        if (wl_comp && xdg_wmbase && wl_shm_obj) {
            struct wl_surface *focus_surf = NULL;
            struct xdg_surface *focus_xdg_surf = NULL;
            struct xdg_toplevel *focus_toplevel = NULL;
            struct wl_buffer *focus_buffer = NULL;

            keyboard_entered = false;
            keyboard_enter_serial = 0;

            struct wl_keyboard *kb = wl_seat_get_keyboard(wl_seat_obj);
            if (kb) wl_keyboard_add_listener(kb, &keyboard_listener, NULL);

            if (create_focus_surface(&focus_surf, &focus_xdg_surf,
                                      &focus_toplevel, &focus_buffer) == 0) {
                /* Event-driven loop: block until keyboard.enter arrives.
                   Timeout: 20 × 100 ms = 2 seconds. */
                int wl_fd = wl_display_get_fd(wl_dpy);
                int timeout_count = 0;
                while (!keyboard_entered && timeout_count < 20) {
                    while (wl_display_prepare_read(wl_dpy) != 0)
                        wl_display_dispatch_pending(wl_dpy);
                    wl_display_flush(wl_dpy);
                    struct pollfd pfd = { .fd = wl_fd, .events = POLLIN };
                    int ret = poll(&pfd, 1, 100);
                    if (ret < 0) {
                        wl_display_cancel_read(wl_dpy);
                        if (errno == EINTR) continue;
                        break;
                    }
                    if (ret == 0) {
                        wl_display_cancel_read(wl_dpy);
                        timeout_count++;
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

                if (keyboard_entered) {
                    wl_data_device_set_selection(wl_dd, copy_source,
                                                 keyboard_enter_serial);
                    wl_display_flush(wl_dpy);
                }

                destroy_focus_surface(focus_surf, focus_xdg_surf,
                                       focus_toplevel, focus_buffer);
            }
            if (kb) wl_keyboard_destroy(kb);
        }

        /* Last-resort — serial=0 (may work on some compositors) */
        if (!keyboard_entered) {
            wl_data_device_set_selection(wl_dd, copy_source, 0);
            wl_display_flush(wl_dpy);
        }
    }

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
    signal(SIGPIPE, SIG_IGN);  /* paste requestor may close pipe mid-transfer */

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

    /* Passing NULL as the source clears PRIMARY — the compositor removes
       any existing selection without taking ownership ourselves, so there
       is nothing left to paste. */
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
    shm_fd = memfd_create("zes-buf", MFD_CLOEXEC);
#endif
    if (shm_fd < 0) {
        char name[] = "/zes-buf-XXXXXX";
        shm_fd = shm_open(name, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
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

/* run_daemon: connect to the Wayland compositor, subscribe to PRIMARY
 * selection events, and loop indefinitely writing changes to the cache.
 * Calls daemon(3) to background itself after creating cache files so
 * the shell never blocks.  See DETECTION ARCHITECTURE comment in the
 * event loop for the full monitoring strategy. */
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

    /* Open persistent fds for write_primary() hot path.
       daemon(0,0) on Linux only redirects fds 0/1/2 to /dev/null; other fds
       survive.  The files already exist from the pre-daemon write_primary() call.
       O_CREAT without O_TRUNC: first real write uses lseek+ftruncate to overwrite. */
    fd_primary = open(primary_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
    fd_seq     = open(seq_path,    O_WRONLY | O_CREAT | O_CLOEXEC, 0644);

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
        free(last_known_content);   /* may be NULL — free(NULL) is safe (C99 §7.20.3.2) */
        last_known_content = NULL;
        if (fd_primary >= 0) { close(fd_primary); fd_primary = -1; }
        if (fd_seq     >= 0) { close(fd_seq);     fd_seq     = -1; }
        unlink(pid_path);
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

    if (fd_primary >= 0) { close(fd_primary); fd_primary = -1; }
    if (fd_seq     >= 0) { close(fd_seq);     fd_seq     = -1; }
    wayland_disconnect();
    free(last_known_content);
    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);
    return 0;
}

/* ===== MAIN ======================================================= */

/* Entry point — parse argv, connect to Wayland, and dispatch to the
 * appropriate sub-function.
 *
 * Modes (first matching flag wins):
 *   (default)          Daemon: background process writing PRIMARY changes to cache.
 *   --oneshot          One-shot read: print PRIMARY text and exit.
 *   --get-clipboard    Print clipboard (CLIPBOARD selection) and exit.
 *   --copy-clipboard   Read stdin, take clipboard ownership, serve paste requests.
 *   --clear-primary    Clear PRIMARY selection.
 *   --help / -h        Print usage to stderr and exit.
 *
 * A positional non-flag argument sets cache_dir (used by daemon / oneshot). */
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
