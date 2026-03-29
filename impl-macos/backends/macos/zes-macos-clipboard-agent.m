// Copyright (c) 2025 Michael Matta
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// macOS clipboard integration agent for zsh-edit-select.
//
// ── ARCHITECTURE ─────────────────────────────────────────────────────
//
//   CGEventTap (passive, listen-only):
//     MouseDown → record position
//               → on main queue: snapshot named-PB changeCounts
//                                + take clipboard backup (g_mousedown_bk)
//     MouseUp   → compute gesture → dispatch handle_mouse_up (0 ms)
//
//   handle_mouse_up(click_count, drag_pixels):
//
//     PATH A — Accessibility API:
//       Read kAXSelectedTextAttribute.  Works: Terminal.app, iTerm2, AppKit.
//       Fails: GPU terminals → kAXErrorAttributeUnsupported.
//       No clipboard involvement.
//
//     UNIFIED ESCALATION (no terminal-specific routing):
//       1. Named PB instant check — captures immediately if terminal
//          already wrote (e.g. Ghostty with copy-on-select=true).
//       2. Start unified watcher:
//          Phase 1 (ticks 0–4): check named PBs only (non-invasive).
//          Phase 2 (tick 5):    inject Cmd+C (escalation).
//          Phase 2+ (ticks 5+): check BOTH named PBs AND clipboard.
//          React to FIRST change detected (action-driven).
//       This covers all terminals without bundleIdentifier checks.
//
//     NON-DEFINITE CLICK PROTECTION:
//       Single clicks (no drag, click_count < 2) where the clipboard
//       changed since mousedown get the clipboard restored.  Prevents
//       terminals that copy on any mouse release from polluting the
//       clipboard.
//
// ── CRITICAL INVARIANT: SEQ IS WRITTEN LAST ──────────────────────────
//   seq mtime is the ZLE change-detection signal.  We write seq AFTER
//   restoring the clipboard so ZLE never reads a stale clipboard.
//   Order: write primary content → restore clipboard → write seq.
//
// ── MOUSEDOWN BACKUP ─────────────────────────────────────────────────
//   g_mousedown_bk captures the clipboard state at MouseDown time,
//   BEFORE any terminal copy-on-select or our own inject.  All paths
//   use this as the restore target.  Unconditional clearContents when
//   backup is empty prevents the "selection copied to clipboard" bug.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <signal.h>
#include <spawn.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* ── Tunables ────────────────────────────────────────────────────────── */
#define DRAG_PX        5.0
#define POLL_NS        (1 * NSEC_PER_MSEC)
#define MAX_POLL_TICKS 300            /* 300 ms safety cap */
#define ESCALATION_TICK 75            /* Wait 75ms before invasive Cmd+C inject */
#define MAX_SEL_SIZE   (4 * 1024 * 1024)
#define MAX_CLIP_SIZE  (4 * 1024 * 1024)
#define DEDUP_SIZE     4096

/* ── Cache filenames ─────────────────────────────────────────────────── */
#define PRIMARY_FILE "primary"
#define SEQ_FILE     "seq"
#define PID_FILE     "agent.pid"

/* ── Path globals ────────────────────────────────────────────────────── */
static char g_cache_dir[512];
static char g_primary_path[560];
static char g_seq_path[560];
static char g_pid_path[560];
static char g_pending_path[560];  /* exists while a watcher is active */

/* ── Persistent fds ──────────────────────────────────────────────────── */
static int g_fd_primary = -1;
static int g_fd_seq     = -1;

/* ── Sequence counter ────────────────────────────────────────────────── */
static _Atomic unsigned long g_seq = 0;

/* ── Shutdown flag ───────────────────────────────────────────────────── */
static volatile sig_atomic_t g_running = 1;

/* ── Event tap ───────────────────────────────────────────────────────── */
static CFMachPortRef      g_tap     = NULL;
static CFRunLoopSourceRef g_tap_rls = NULL;

/* ── Dedup cache ─────────────────────────────────────────────────────── */
static char   g_last[DEDUP_SIZE];
static size_t g_last_len = 0;

/* ── Mouse-down position ─────────────────────────────────────────────── */
static CGFloat g_down_x = 0.0;
static CGFloat g_down_y = 0.0;

/* ── MouseDown clipboard backup ──────────────────────────────────────── */
/* Captured at MouseDown, BEFORE any terminal copy-on-select or our inject.
   Used as the restore target in all capture paths. */
static NSArray   *g_mousedown_bk = nil;  /* ARC managed */
static NSInteger  g_mousedown_cc = -1;   /* changeCount at MouseDown */

/* ── Named-PB snapshot ───────────────────────────────────────────────── */
#define MAX_NAMED_PBS 4
static NSPasteboard *g_named_pb[MAX_NAMED_PBS];
static NSInteger     g_named_pb_cc[MAX_NAMED_PBS];
static int           g_num_named_pb = 0;

/* ── Watcher state ───────────────────────────────────────────────────── */
static uint64_t          g_gen     = 0;
static dispatch_source_t g_watcher = NULL;

/* ─────────────────────────────────────────────────────────────────────
   write_primary_content()
   Write ONLY the primary content file.  Does NOT update the seq file.
   Updates the dedup cache and increments g_seq.
   Returns the length written, or 0 if deduped (identical content).
   ───────────────────────────────────────────────────────────────────── */
static size_t write_primary_content(const char *utf8, size_t len) {
    if (!utf8) utf8 = "";
    if (len > MAX_SEL_SIZE) len = MAX_SEL_SIZE;

    /* Dedup check */
    if (len == g_last_len && len < DEDUP_SIZE &&
        (len == 0 || (g_last[0] != '\0' && memcmp(g_last, utf8, len) == 0))) return 0;

    /* If previous was not empty and current is empty, return 1 to signal deselection */
    if (len == 0 && g_last_len > 0) {
        g_last[0] = '\0'; g_last_len = 0;
        g_seq++;
        /* Truncate the file so reading it yields nothing */
        if (g_fd_primary >= 0) {
            (void)ftruncate(g_fd_primary, 0);
        } else {
            int fd = open(g_primary_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
            if (fd >= 0) close(fd);
        }
        return 1;
    } else {
        /* Update normal dedup cache */
        if (len < DEDUP_SIZE) { memcpy(g_last, utf8, len); g_last[len] = '\0'; }
        else                  { g_last[0] = '\0'; }
        g_last_len = len;
        g_seq++;
    }

    /* Write primary file (NOT seq yet) */
    if (g_fd_primary >= 0) {
        ssize_t r = pwrite(g_fd_primary, utf8, len, 0); (void)r;
        (void)ftruncate(g_fd_primary, (off_t)len);
    } else {
        int fd = open(g_primary_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
        if (fd >= 0) { ssize_t r = write(fd, utf8, len); (void)r; close(fd); }
    }
    return len > 0 ? len : 1;
}

/* ─────────────────────────────────────────────────────────────────────
   flush_seq()
   Write ONLY the seq file, signalling ZLE that primary changed.
   Called AFTER clipboard is restored so ZLE reads a clean clipboard.
   ───────────────────────────────────────────────────────────────────── */
static void flush_seq(void) {
    unsigned long seq = g_seq;
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
    if (g_fd_seq >= 0) {
        ssize_t r = pwrite(g_fd_seq, buf, (size_t)n, 0); (void)r;
        (void)ftruncate(g_fd_seq, (off_t)n);
    } else {
        int fd = open(g_seq_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
        if (fd >= 0) { ssize_t r = write(fd, buf, (size_t)n); (void)r; close(fd); }
    }
}

/* ─────────────────────────────────────────────────────────────────────
   write_primary()  — used only by modes that don't need split write.
   ───────────────────────────────────────────────────────────────────── */
static void write_primary(const char *data, size_t len, unsigned long seq) {
    if (g_fd_primary >= 0 && g_fd_seq >= 0) {
        if (len > 0 && data) { ssize_t r = pwrite(g_fd_primary, data, len, 0); (void)r; }
        (void)ftruncate(g_fd_primary, (off_t)len);
        char buf[32];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = pwrite(g_fd_seq, buf, (size_t)n, 0); (void)r;
        (void)ftruncate(g_fd_seq, (off_t)n);
        return;
    }
    int fd = open(g_primary_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
    if (fd >= 0) {
        if (len > 0 && data) { ssize_t r = write(fd, data, len); (void)r; }
        close(fd);
    }
    fd = open(g_seq_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
    if (fd >= 0) {
        char buf[32];
        int n = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = write(fd, buf, (size_t)n); (void)r;
        close(fd);
    }
}

/* ensure_cache_dir()  Priority: explicit arg > $TMPDIR > /tmp */
static int ensure_cache_dir(const char *dir) {
    if (dir && dir[0]) {
        snprintf(g_cache_dir, sizeof(g_cache_dir), "%s", dir);
    } else {
        const char *t = getenv("TMPDIR");
        if (t && t[0])
            snprintf(g_cache_dir, sizeof(g_cache_dir), "%s/zsh-edit-select-%d", t, (int)getuid());
        else
            snprintf(g_cache_dir, sizeof(g_cache_dir), "/tmp/zsh-edit-select-%d", (int)getuid());
    }
    snprintf(g_primary_path,  sizeof(g_primary_path),  "%s/%s",      g_cache_dir, PRIMARY_FILE);
    snprintf(g_seq_path,      sizeof(g_seq_path),      "%s/%s",      g_cache_dir, SEQ_FILE);
    snprintf(g_pid_path,      sizeof(g_pid_path),      "%s/%s",      g_cache_dir, PID_FILE);
    snprintf(g_pending_path,  sizeof(g_pending_path),  "%s/pending", g_cache_dir);
    struct stat st;
    if (stat(g_cache_dir, &st) == -1)
        if (mkdir(g_cache_dir, 0700) == -1 && errno != EEXIST) return -1;
    return 0;
}

/* clear_primary_cache() — AX reported empty selection. */
static void clear_primary_cache(void) {
    if (g_last_len > 0) {
        g_last[0] = '\0'; g_last_len = 0;
        g_seq++; write_primary("", 0, g_seq);
    }
}

static void cancel_watcher(void) {
    if (g_watcher) { dispatch_source_cancel(g_watcher); g_watcher = NULL; }
}

static void create_pending_marker(void) {
    if (!g_pending_path[0]) return;
    int fd = open(g_pending_path, O_WRONLY|O_CREAT|O_TRUNC|O_CLOEXEC, 0644);
    if (fd >= 0) close(fd);
}
static void delete_pending_marker(void) {
    if (g_pending_path[0]) unlink(g_pending_path);
}

/* ─────────────────────────────────────────────────────────────────────
   clipboard_restore_to_mousedown()
   Restore generalPasteboard to the state captured at MouseDown.
   This undoes both terminal copy-on-select AND our own Cmd+C inject.
   Uses TransientType so clipboard history managers ignore the write.
   UNCONDITIONAL: always restores, even if backup is empty (in which
   case it just clears the clipboard — correct, since it was empty).
   ───────────────────────────────────────────────────────────────────── */
static void clipboard_restore_to_mousedown(void) {
    @autoreleasepool {
        if (g_mousedown_bk == nil) return;
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        if (g_mousedown_bk.count > 0) {
            NSPasteboardItem *marker = [[NSPasteboardItem alloc] init];
            [marker setString:@"" forType:@"org.nspasteboard.TransientType"];
            NSMutableArray *all = [NSMutableArray arrayWithObject:marker];
            [all addObjectsFromArray:g_mousedown_bk];
            [pb writeObjects:all];
        }
        /* If count == 0: clipboard was empty at MouseDown → clearContents is correct. */
    }
}

/* ─────────────────────────────────────────────────────────────────────
   finalize_selection(utf8, len, delay_restore)
   Central commit point used by ALL capture paths.
   If delay_restore is true, wait 15ms before restoring clipboard & deleting
   pending marker. This sweeps up asynchronous clipboard pollution from
   terminals like Ghostty that copy-on-select to the system clipboard
   *after* writing the named PB.
   ───────────────────────────────────────────────────────────────────── */
static void finalize_selection(const char *utf8, size_t len, bool delay_restore) {
    size_t written = write_primary_content(utf8, len);
    if (!written && len > 0) {
        /* Dedup: same content as last time. */
        if (delay_restore) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                clipboard_restore_to_mousedown();
                delete_pending_marker();
            });
        } else {
            clipboard_restore_to_mousedown();
            delete_pending_marker();
        }
        return;
    }

    /* If written is 0 but len is 0, it means it's a deselection (already empty).
       We still want to flush seq and delete marker to be absolutely sure ZLE continues. */
    if (delay_restore) {
        flush_seq(); /* Primary & seq written, ZLE has text immediately */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 40 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            clipboard_restore_to_mousedown();
            delete_pending_marker();
        });
    } else {
        clipboard_restore_to_mousedown();   /* restore BEFORE seq write */
        flush_seq();                        /* signal ZLE — safe now */
        delete_pending_marker();
    }
}

/* ─────────────────────────────────────────────────────────────────────
   PATH A — Accessibility API
   Returns:
      1  text captured.
      0  AX-capable + empty selection → primary cleared.
     -1  kAXErrorAttributeUnsupported: GPU terminal → try Path B/C.
     -2  no focus / other error → do nothing.
   ───────────────────────────────────────────────────────────────────── */
static int ax_try(void) {
    @autoreleasepool {
        AXUIElementRef sw = AXUIElementCreateSystemWide();
        if (!sw) return -2;

        AXUIElementRef focused = NULL;
        AXError e = AXUIElementCopyAttributeValue(sw, kAXFocusedUIElementAttribute,
                                                  (CFTypeRef *)&focused);
        CFRelease(sw);
        if (e != kAXErrorSuccess || !focused) return -2;

        CFTypeRef val = NULL;
        e = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute, &val);
        CFRelease(focused);

        if (e == kAXErrorAttributeUnsupported || e == kAXErrorActionUnsupported)
            return -1;   /* GPU terminal */
        if (e != kAXErrorSuccess || !val) return -2;

        NSString *s = (__bridge_transfer NSString *)val;
        if (!s || s.length == 0) { clear_primary_cache(); return 0; }
        const char *utf8 = [s UTF8String];
        if (!utf8) return -2;
        /* Path A: no clipboard involvement, no finalize_selection needed.
           We can use commit_selection directly (no clipboard to restore). */
        if (g_last_len == strlen(utf8) && strlen(utf8) < DEDUP_SIZE &&
            g_last[0] != '\0' && memcmp(g_last, utf8, strlen(utf8)) == 0) {
            return 1; /* dedup */
        }
        size_t len = strlen(utf8);
        if (len < DEDUP_SIZE) { memcpy(g_last, utf8, len); g_last[len] = '\0'; }
        else                  { g_last[0] = '\0'; }
        g_last_len = len;
        g_seq++;
        write_primary(utf8, len, g_seq);
        return 1;
    }
}

/* ─────────────────────────────────────────────────────────────────────
   PATH B — Named Selection Pasteboard (Ghostty)
   ───────────────────────────────────────────────────────────────────── */
static void named_pb_init(void) {
    @autoreleasepool {
        static const char *names[] = {
            "com.mitchellh.ghostty.selection",  /* index 0 */
            "com.apple.Terminal.selection",     /* index 1 */
            NULL
        };
        g_num_named_pb = 0;
        for (int i = 0; names[i] && g_num_named_pb < MAX_NAMED_PBS; i++) {
            NSPasteboard *pb = [NSPasteboard pasteboardWithName:@(names[i])];
            if (pb) {
                g_named_pb[g_num_named_pb]    = pb;
                g_named_pb_cc[g_num_named_pb] = -1;
                g_num_named_pb++;
            }
        }
    }
}

static void named_pb_snapshot(void) {
    @autoreleasepool {
        for (int i = 0; i < g_num_named_pb; i++)
            g_named_pb_cc[i] = g_named_pb[i].changeCount;
    }
}

/* Try to capture from named PBs immediately.  Returns true if captured. */
static bool named_pb_try(void) {
    @autoreleasepool {
        for (int i = 0; i < g_num_named_pb; i++) {
            NSInteger cur = g_named_pb[i].changeCount;
            if (g_named_pb_cc[i] >= 0 && cur == g_named_pb_cc[i]) continue;
            NSString *str = [g_named_pb[i] stringForType:NSPasteboardTypeString];
            /* Allow empty strings (deselection) to be finalized. */
            if (!str) str = @"";
            const char *utf8 = [str UTF8String];
            if (!utf8) utf8 = "";
            finalize_selection(utf8, strlen(utf8), true);
            return true;
        }
        return false;
    }
}

/* ─────────────────────────────────────────────────────────────────────
   Cmd+C injection — used as escalation step in the unified watcher.
   ───────────────────────────────────────────────────────────────────── */
static void inject_cmd_c(void) {
    CGEventRef dn = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x08, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)0x08, false);
    if (dn && up) {
        CGEventSetFlags(dn, kCGEventFlagMaskCommand);
        CGEventSetFlags(up, kCGEventFlagMaskCommand);
        CGEventPost(kCGAnnotatedSessionEventTap, dn);
        CGEventPost(kCGAnnotatedSessionEventTap, up);
    }
    if (dn) CFRelease(dn);
    if (up) CFRelease(up);
}

/* ─────────────────────────────────────────────────────────────────────
   UNIFIED WATCHER — replaces start_named_pb_watcher + start_cmdc_watcher

   Action-driven escalation strategy (no terminal-specific routing):
     Phase 1 (ticks 0 to ESCALATION_TICK-1):
       Check named PBs only.  Non-invasive — covers terminals that
       write to a named PB on selection (e.g. Ghostty copy-on-select=true).
     Phase 2 (tick == ESCALATION_TICK):
       Inject Cmd+C.  Captures cc_inject_before for clipboard detection.
     Phase 2+ (ticks > ESCALATION_TICK):
       Check BOTH named PBs AND clipboard changeCount.
       Covers all terminals that respond to Cmd+C.
     Terminates on FIRST change detected (action-driven) or MAX_POLL_TICKS.
   ───────────────────────────────────────────────────────────────────── */
static void start_unified_watcher(uint64_t gen) {
    __block int ticks = 0;
    __block NSInteger cc_inject_before = -1;  /* set at escalation time */
    __block bool injected = false;

    dispatch_source_t w = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(w, DISPATCH_TIME_NOW, POLL_NS, 0);

    dispatch_source_set_event_handler(w, ^{
        @autoreleasepool {
            if (!g_running || g_gen != gen) {
                g_watcher = NULL;
                dispatch_source_cancel(w);
                delete_pending_marker();
                return;
            }

            /* ── Check named PBs (all phases) ──────────────────────── */
            for (int i = 0; i < g_num_named_pb; i++) {
                NSInteger cur = g_named_pb[i].changeCount;
                if (g_named_pb_cc[i] >= 0 && cur == g_named_pb_cc[i]) continue;
                NSString *str = [g_named_pb[i] stringForType:NSPasteboardTypeString];
                g_watcher = NULL;
                dispatch_source_cancel(w);
                /* Allow empty strings (deselection) to be finalized. */
                const char *utf8 = (str && str.length > 0) ? [str UTF8String] : "";
                if (!utf8) utf8 = "";
                finalize_selection(utf8, strlen(utf8), true);
                return;
            }

            /* ── Phase 1: Native Copy-On-Select (Instant clipboard catch) ── */
            if (!injected) {
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                NSInteger cur = pb.changeCount;
                if (g_mousedown_cc >= 0 && cur != g_mousedown_cc) {
                    NSString *str = [pb stringForType:NSPasteboardTypeString];
                    if (str && str.length > 0) {
                        g_watcher = NULL;
                        dispatch_source_cancel(w);
                        const char *utf8 = [str UTF8String];
                        finalize_selection(utf8, strlen(utf8), true);
                        return;
                    }
                    /* Terminal bumped changeCount but hasn't provided text yet. Wait. */
                }
            }

            /* ── Phase 2: Escalation — inject Cmd+C ────────────────── */
            if (!injected && ticks >= ESCALATION_TICK) {
                injected = true;
                cc_inject_before = [[NSPasteboard generalPasteboard] changeCount];
                inject_cmd_c();
            }

            /* ── Phase 2+: Check clipboard (after inject) ──────────── */
            if (injected) {
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                NSInteger cur = pb.changeCount;
                if (cur != cc_inject_before) {
                    NSString *str = [pb stringForType:NSPasteboardTypeString];
                    if (str && str.length > 0) {
                        g_watcher = NULL;
                        dispatch_source_cancel(w);
                        const char *utf8 = [str UTF8String];
                        finalize_selection(utf8, strlen(utf8), true);
                        return;
                    }
                    /* Terminal bumped changeCount but hasn't provided text yet. Wait. */
                }
            }

            /* ── Timeout ───────────────────────────────────────────── */
            if (++ticks >= MAX_POLL_TICKS) {
                g_watcher = NULL;
                dispatch_source_cancel(w);
                clipboard_restore_to_mousedown();
                delete_pending_marker();

                /* DESELECTION FALLBACK:
                   If the watcher timed out, it means the terminal natively chose
                   NOT to copy any text to the clipboard (e.g., user dragged slightly
                   or double-clicked an empty space). We MUST clear the stale cache
                   preventing ZSH from hallucinating a phantom selection. */
                clear_primary_cache();
            }
        }
    });
    g_watcher = w;
    dispatch_resume(w);
}

/* ─────────────────────────────────────────────────────────────────────
   handle_mouse_up()
   Unified, terminal-agnostic handling.  No bundleIdentifier checks.
   ───────────────────────────────────────────────────────────────────── */
static void handle_mouse_up(NSInteger click_count, CGFloat drag_pixels) {
    if (!g_running) return;
    cancel_watcher();
    g_gen++;

    /* Path A — Accessibility API */
    int ax = ax_try();
    if (ax != -1) {
        /* AX succeeded or terminal is AX-capable.  For non-definite
           clicks that are AX-capable, no clipboard protection needed
           (AX doesn't touch clipboard). */
        return;
    }

    /* GPU terminal confirmed (AX returned -1). */
    bool definite = (click_count >= 2) || (drag_pixels > DRAG_PX);

    if (!definite) {
        /* Non-definite click: restore clipboard if terminal's mouse-Up
           handler copied to clipboard (copy-on-any-click protection).
           Compares changeCount to detect unwanted clipboard writes. */
        @autoreleasepool {
            NSInteger cur = [[NSPasteboard generalPasteboard] changeCount];
            if (g_mousedown_cc >= 0 && cur != g_mousedown_cc) {
                clipboard_restore_to_mousedown();
            }
        }
        /* DESELECTION FALLBACK: If a terminal is frontmost and no selection was found
           via AX or Named PB, clear cache. This solves the Phantom Bug for GPU terms. */
        @autoreleasepool {
            NSRunningApplication *front = [[NSWorkspace sharedWorkspace] frontmostApplication];
            if (front && front.active) {
                 clear_primary_cache();
            }
        }
        return;
    }

    uint64_t gen = g_gen;
    create_pending_marker();

    /* Try named PBs immediately (fast path — terminal already wrote). */
    if (named_pb_try()) return;

    /* Unified escalation: named PBs → Cmd+C inject → first-change wins. */
    start_unified_watcher(gen);
}

/* ─────────────────────────────────────────────────────────────────────
   event_tap_callback()
   MouseDown: record position + (on main queue) snapshot + backup.
   MouseUp:   compute gesture + dispatch handle_mouse_up.
   ───────────────────────────────────────────────────────────────────── */
static CGEventRef event_tap_callback(CGEventTapProxy proxy,
                                     CGEventType type,
                                     CGEventRef event,
                                     void *refcon) {
    (void)proxy; (void)refcon;

    if (type == kCGEventTapDisabledByTimeout ||
        type == kCGEventTapDisabledByUserInput) {
        if (g_tap) CGEventTapEnable(g_tap, true);
        return event;
    }
    if (!g_running) return event;

    if (type == kCGEventLeftMouseDown) {
        CGPoint p = CGEventGetLocation(event);
        g_down_x = p.x; g_down_y = p.y;
        dispatch_async(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                /* Snapshot named-PBs AND take clipboard backup.
                   Both must happen BEFORE any terminal write. */
                named_pb_snapshot();
                NSPasteboard *pb = [NSPasteboard generalPasteboard];
                g_mousedown_cc = pb.changeCount;
                NSArray<NSPasteboardItem *> *items = pb.pasteboardItems;
                if (!items.count) {
                    g_mousedown_bk = @[];
                } else {
                    NSMutableArray *bk = [NSMutableArray arrayWithCapacity:items.count];
                    for (NSPasteboardItem *item in items) {
                        NSPasteboardItem *copy = [[NSPasteboardItem alloc] init];
                        for (NSString *t in item.types) {
                            NSData *d = [item dataForType:t];
                            if (d) [copy setData:[d copy] forType:t];
                        }
                        [bk addObject:copy];
                    }
                    g_mousedown_bk = [bk copy];
                }
            }
        });
    }
    else if (type == kCGEventLeftMouseUp) {
        CGPoint   p    = CGEventGetLocation(event);
        CGFloat   drag = sqrt((p.x-g_down_x)*(p.x-g_down_x) +
                              (p.y-g_down_y)*(p.y-g_down_y));
        NSInteger cc   = CGEventGetIntegerValueField(event, kCGMouseEventClickState);
        CGFloat   d    = drag;
        NSInteger c    = cc;
        dispatch_async(dispatch_get_main_queue(), ^{ handle_mouse_up(c, d); });
    }
    return event;
}

/* ── Utility functions ───────────────────────────────────────────────── */
static char *get_clipboard_utf8(size_t *out_len) {
    *out_len = 0;
    NSPasteboard *pb  = [NSPasteboard generalPasteboard];
    NSString     *str = [pb stringForType:NSPasteboardTypeString];
    if (!str) return NULL;
    const char *utf8 = [str UTF8String];
    if (!utf8) return NULL;
    size_t len = strlen(utf8);
    if (!len || len > MAX_CLIP_SIZE) return NULL;
    char *buf = malloc(len + 1);
    if (!buf) return NULL;
    memcpy(buf, utf8, len); buf[len] = '\0'; *out_len = len;
    return buf;
}

static bool set_clipboard_utf8(const char *data, size_t len) {
    if (!data || !len) return false;
    NSString *str = [[NSString alloc] initWithBytes:data length:len
                                           encoding:NSUTF8StringEncoding];
    if (!str) str = [[NSString alloc] initWithBytes:data length:len
                                           encoding:NSISOLatin1StringEncoding];
    if (!str) return false;
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    return [pb setString:str forType:NSPasteboardTypeString];
}

static char *read_all_stdin(size_t *out_len) {
    size_t cap = 4096, total = 0;
    char  *buf = malloc(cap);
    if (!buf) { *out_len = 0; return NULL; }
    for (;;) {
        if (total + 4096 > cap) {
            cap *= 2;
            if (cap > MAX_CLIP_SIZE) break;
            char *nb = realloc(buf, cap);
            if (!nb) { free(buf); *out_len = 0; return NULL; }
            buf = nb;
        }
        ssize_t n = read(STDIN_FILENO, buf + total, 4096);
        if (n > 0) total += (size_t)n; else break;
    }
    *out_len = total; return buf;
}

/* ── Short-lived modes ───────────────────────────────────────────────── */
static int run_oneshot(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSApplication sharedApplication]
            setActivationPolicy:NSApplicationActivationPolicyAccessory];
        size_t len = 0; char *data = get_clipboard_utf8(&len);
        if (data && len) { fwrite(data, 1, len, stdout); free(data); return 0; }
        free(data); return 1;
    }
}

static int run_copy_clipboard(void) {
    size_t len = 0; char *data = read_all_stdin(&len);
    if (!data || !len) { free(data); return 1; }
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSApplication sharedApplication]
            setActivationPolicy:NSApplicationActivationPolicyAccessory];
        bool ok = set_clipboard_utf8(data, len);
        free(data); return ok ? 0 : 1;
    }
}

static int run_clear_primary(void) {
    g_seq++; write_primary("", 0, g_seq); return 0;
}

static int run_status(const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stdout, "status: cache directory unavailable\n"); return 1;
    }
    bool alive = false; pid_t dpid = 0;
    FILE *pf = fopen(g_pid_path, "r");
    if (pf) {
        if (fscanf(pf, "%d", &dpid) == 1 && dpid > 0) alive = (kill(dpid, 0) == 0);
        fclose(pf);
    }
    char preview[64] = "(empty)";
    FILE *prf = fopen(g_primary_path, "r");
    if (prf) {
        size_t n = fread(preview, 1, sizeof(preview)-1, prf);
        preview[n] = '\0';
        for (size_t i = 0; i < n; i++) if (preview[i] == '\n') preview[i] = ' ';
        fclose(prf);
        if (n == 0) strcpy(preview, "(empty)");
        else if (n == sizeof(preview)-1) strcpy(preview+60, "...");
    }
    bool ax = AXIsProcessTrusted();
    char pid_buf[32] = "";
    if (alive) snprintf(pid_buf, sizeof(pid_buf), "%d)", dpid);
    fprintf(stdout,
        "zes-macos-clipboard-agent v1.0.3\n"
        "  daemon pid    : %s%s\n"
        "  accessibility : %s\n"
        "  cache dir     : %s\n"
        "  primary now   : \"%s\"\n"
        "  selection path: %s\n",
        alive ? "running (pid " : "NOT RUNNING", pid_buf,
        ax ? "granted" : "NOT GRANTED (run: edit-select setup-ax)",
        g_cache_dir, preview,
        ax ? "AX (AppKit) + Named PB (Ghostty) + Cmd+C inject (others)"
           : "disabled (no Accessibility permission)");
    return alive ? 0 : 1;
}

/* ── Daemon ──────────────────────────────────────────────────────────── */
static int run_daemon_worker(const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) return 1;
    setsid();

    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSApplication sharedApplication]
            setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }

    named_pb_init();

    { int dn = open("/dev/null", O_RDWR|O_CLOEXEC);
      if (dn >= 0) { dup2(dn,0); dup2(dn,1); dup2(dn,2); if (dn>2) close(dn); } }

    { FILE *f = fopen(g_pid_path, "w");
      if (f) { fprintf(f, "%d\n", getpid()); fclose(f); } }

    g_fd_primary = open(g_primary_path, O_WRONLY|O_CREAT|O_CLOEXEC, 0644);
    g_fd_seq     = open(g_seq_path,     O_WRONLY|O_CREAT|O_CLOEXEC, 0644);

    signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN); signal(SIGHUP, SIG_IGN);
    void (^stop)(void) = ^{ g_running = 0; CFRunLoopStop(CFRunLoopGetMain()); };
    dispatch_source_t st = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(st, stop); dispatch_resume(st);
    dispatch_source_t si = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT,  0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(si, stop); dispatch_resume(si);
    dispatch_source_t sh = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGHUP,  0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(sh, stop); dispatch_resume(sh);

    if (AXIsProcessTrusted()) {
        CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseDown) |
                           CGEventMaskBit(kCGEventLeftMouseUp);
        g_tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
                                 kCGEventTapOptionListenOnly, mask,
                                 event_tap_callback, NULL);
        if (g_tap) {
            g_tap_rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_tap, 0);
            if (g_tap_rls) {
                CFRunLoopAddSource(CFRunLoopGetMain(), g_tap_rls, kCFRunLoopDefaultMode);
                CGEventTapEnable(g_tap, true);
            }
        }
    }

    CFRunLoopRun();

    g_running = 0;
    cancel_watcher();
    delete_pending_marker();
    dispatch_source_cancel(st); dispatch_source_cancel(si); dispatch_source_cancel(sh);
    if (g_tap) {
        CGEventTapEnable(g_tap, false);
        if (g_tap_rls) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), g_tap_rls, kCFRunLoopDefaultMode);
            CFRelease(g_tap_rls); g_tap_rls = NULL;
        }
        CFRelease(g_tap); g_tap = NULL;
    }
    if (g_fd_primary >= 0) { close(g_fd_primary); g_fd_primary = -1; }
    if (g_fd_seq     >= 0) { close(g_fd_seq);     g_fd_seq     = -1; }
    unlink(g_primary_path); unlink(g_seq_path);
    unlink(g_pid_path); unlink(g_pending_path);
    return 0;
}

static int run_daemon(const char *exe_path, const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "zes-macos-clipboard-agent: cannot create cache dir\n");
        return 1;
    }
    g_seq = (unsigned long)time(NULL);
    write_primary("", 0, g_seq);

    pid_t pid;
    const char *argv[] = { exe_path, "--_daemon-child", cache_dir_arg, NULL };
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
#ifdef POSIX_SPAWN_SETSID
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);
#endif
    int ret = posix_spawn(&pid, exe_path, NULL, &attr, (char *const *)argv, environ);
    posix_spawnattr_destroy(&attr);
    if (ret != 0) {
        fprintf(stderr, "zes-macos-clipboard-agent: posix_spawn failed: %d\n", ret);
        return 1;
    }
    return 0;
}

/* ── main() ──────────────────────────────────────────────────────────── */
int main(int argc, char *argv[]) {
    const char *cache_dir_arg = NULL;
    bool oneshot=0, get_clip=0, copy_clip=0, clr_prim=0,
         chk_ax=0, req_ax=0, child=0, status=0;

    for (int i = 1; i < argc; i++) {
        if      (!strcmp(argv[i],"--oneshot"))        oneshot   = true;
        else if (!strcmp(argv[i],"--get-clipboard"))  get_clip  = true;
        else if (!strcmp(argv[i],"--copy-clipboard")) copy_clip = true;
        else if (!strcmp(argv[i],"--clear-primary"))  clr_prim  = true;
        else if (!strcmp(argv[i],"--check-ax"))       chk_ax    = true;
        else if (!strcmp(argv[i],"--request-ax"))     req_ax    = true;
        else if (!strcmp(argv[i],"--_daemon-child"))  child     = true;
        else if (!strcmp(argv[i],"--status"))         status    = true;
        else if (!strcmp(argv[i],"--help")||!strcmp(argv[i],"-h")) {
            fprintf(stderr,
                "Usage: %s [cache_dir] [OPTIONS]\n"
                "zsh-edit-select macOS primary selection agent v1.0.3\n\n"
                "  (default)         Daemon\n"
                "  --oneshot         Print clipboard and exit\n"
                "  --get-clipboard   Alias for --oneshot\n"
                "  --copy-clipboard  Read stdin, write to clipboard, exit\n"
                "  --clear-primary   Clear cache files only\n"
                "  --check-ax        Exit 0 if Accessibility granted\n"
                "  --request-ax      Prompt for Accessibility permission\n"
                "  --status          Print daemon status\n",
                argv[0]);
            return 0;
        } else { cache_dir_arg = argv[i]; }
    }

    if (chk_ax)  return AXIsProcessTrusted() ? 0 : 1;
    if (status)  return run_status(cache_dir_arg);
    if (req_ax) {
        @autoreleasepool {
            NSDictionary *opts = @{ (__bridge id)kAXTrustedCheckOptionPrompt : @YES };
            return AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts) ? 0 : 1;
        }
    }
    if (clr_prim) {
        if (ensure_cache_dir(cache_dir_arg) != 0) return 1;
        FILE *f = fopen(g_seq_path, "r");
        if (f) { unsigned long tmp=0;
                 g_seq = (fscanf(f,"%lu",&tmp)==1) ? tmp : (unsigned long)time(NULL);
                 fclose(f); }
        else   { g_seq = (unsigned long)time(NULL); }
        return run_clear_primary();
    }
    if (oneshot || get_clip) return run_oneshot();
    if (copy_clip)           return run_copy_clipboard();
    if (child)               return run_daemon_worker(cache_dir_arg);
    return run_daemon(argv[0], cache_dir_arg);
}
