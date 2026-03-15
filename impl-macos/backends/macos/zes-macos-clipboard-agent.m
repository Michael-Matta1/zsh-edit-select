// Copyright (c) 2025 Michael Matta
// Version: 0.6.3
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// macOS clipboard integration agent for zsh-edit-select.
//
// PRIMARY SELECTION ARCHITECTURE (AX-ONLY):
// This agent implements true X11-PRIMARY-equivalent semantics on macOS.
// There is ONE and only ONE channel by which mouse selections are detected:
//
//   kCGEventLeftMouseUp (CGEventTap) → kAXSelectedTextAttribute (AX API)
//
// When the mouse button releases, selection is complete. We read the
// selected text via kAXSelectedTextAttribute. If non-empty and changed,
// we write it to the primary cache. The clipboard (NSPasteboard) is
// NEVER touched by a mouse drag. This is NOT Copy-on-Select.
//
// For terminals with custom GPU renderers (Kitty, Alacritty, WezTerm,
// Ghostty), kAXSelectedTextAttribute returns kAXErrorAttributeUnsupported.
// We silently skip — no fallback, no Copy-on-Select, no error.
//
// DAEMONIZATION: fork()+setsid() — NOT daemon(3).
//   daemon(3) moves the process to the root bootstrap namespace, breaking
//   NSPasteboard access. fork()+setsid() preserves user bootstrap namespace.
//
// SIGNAL HANDLING: GCD dispatch sources on main queue — NOT signal().
//   CFRunLoopRun() is not async-signal-safe. GCD signal dispatch sources
//   run their handlers on the specified queue (main queue here), which is
//   safe to call CFRunLoopStop() from.
//
// COCOA INIT: [NSApplication sharedApplication] + setActivationPolicy:
//   NSApplicationActivationPolicyAccessory called in main() BEFORE fork(),
//   so the child inherits the established pboard Mach port.
//   setActivationPolicy:Accessory is required for CGEventTapCreate to
//   succeed on macOS 15 Sequoia (see Correction P).
//   NSApplicationLoad() is deprecated since macOS 10.15 — NOT used.
//
// Operation modes (first matching flag wins):
//   (default)           Daemon: CGEventTap for AX mouse selection.
//   [cache_dir]         Daemon with explicit cache directory.
//   --oneshot           Print current clipboard text and exit.
//   --get-clipboard     Alias for --oneshot.
//   --copy-clipboard    Read stdin, write to NSPasteboard, exit.
//   --clear-primary     Clear local cache files only (NOT NSPasteboard).
//   --check-ax          Exit 0 if Accessibility granted, 1 if not.
//   --request-ax        Prompt for Accessibility permission; exit 0 if granted.
//   --help / -h         Print usage to stderr and exit 0.

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dispatch/dispatch.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h> /* _Atomic for g_seq_counter */
#include <stdbool.h>
#include <sys/stat.h>
#include <time.h>

/* ── Cache-directory filenames ───────────────────────────────────────── */
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "agent.pid"
#define MAX_CLIPBOARD_SIZE (4 * 1024 * 1024)

/* AX deduplication cache. Selections larger than this are written
   without deduplication (large selections are rare in terminals). */
#define AX_DEDUP_CACHE_SIZE 4096

/* ── Global path strings ─────────────────────────────────────────────── */
static char g_cache_dir[512];
static char g_primary_path[560];
static char g_seq_path[560];
static char g_pid_path[560];

/* ── Persistent file descriptors (hot path) ──────────────────────────── */
/* Opened once after daemonization. Reused for all writes. -1 = not open. */
static int g_fd_primary = -1;
static int g_fd_seq = -1;

/* ── Sequence counter ────────────────────────────────────────────────── */
/* Seeded with time(NULL) at startup — monotonically larger than any prior
   session, preventing false positives after daemon restart.
   _Atomic: defensive correctness; with AX-only all writes happen on the
   main queue (single thread), so no data race exists. _Atomic adds one
   store-release barrier (~2ns on Apple Silicon) per increment — unmeasurable
   given increments fire only on mouse button releases. */
static _Atomic unsigned long g_seq_counter = 0;

/* ── Shutdown flag ───────────────────────────────────────────────────── */
/* Set by GCD signal dispatch source handlers. Used as a fence for
   conditional blocks inside the CGEventTap callback. */
static volatile sig_atomic_t g_running = 1;

/* ── CGEventTap state ────────────────────────────────────────────────── */
static CFMachPortRef g_event_tap = NULL;
static CFRunLoopSourceRef g_tap_rls = NULL;

/* ── AX deduplication cache ──────────────────────────────────────────── */
/* g_last_ax_selection: last text written via AX path. Stack-allocated.
   g_last_ax_selection_len: byte count of cached text. 0 = none cached.
   Used to avoid writing identical content on repeat clicks to same location
   and to detect "selection cleared" transitions (non-empty → empty). */
static char g_last_ax_selection[AX_DEDUP_CACHE_SIZE];
static size_t g_last_ax_selection_len = 0;

/* ─────────────────────────────────────────────────────────────────────
   write_primary()
   Write selection text and sequence counter to cache files.

   HOT PATH (persistent fds — after daemonization):
     pwrite(fd_primary, data, len, 0)  — write from offset 0
     ftruncate(fd_primary, len)        — MANDATORY: removes stale trailing
                                         bytes when new content is shorter
     pwrite(fd_seq, counter_str, n, 0) — update seq LAST
     ftruncate(fd_seq, n)
   WRITE ORDER INVARIANT: primary MUST be fully committed before seq is
   touched. seq's mtime is the shell's ONLY change-detection signal.
   Touching seq last guarantees primary is consistent when shell reads it.

   FALLBACK PATH (pre-daemonization / short-lived modes):
     open/write/close per file. Correct but slower.
   ───────────────────────────────────────────────────────────────────── */
static void write_primary(const char *data, size_t len, unsigned long seq) {
  if (g_fd_primary >= 0 && g_fd_seq >= 0) {
    /* Hot path: persistent fds. */
    if (len > 0 && data) {
      ssize_t r = pwrite(g_fd_primary, data, len, 0);
      (void)r;
    }
    (void)ftruncate(g_fd_primary, (off_t)len);

    char buf[32];
    /* Alternate file size (add space for even seq) to guarantee Zsh
       detects stat +size changes even within the same second. */
    int n = snprintf(buf, sizeof(buf), "%lu%s\n", seq, (seq % 2 == 0) ? " " : "");
    ssize_t r = pwrite(g_fd_seq, buf, (size_t)n, 0);
    (void)r;
    (void)ftruncate(g_fd_seq, (off_t)n);
    return;
  }

  /* Fallback path. */
  int fd = open(g_primary_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (fd >= 0) {
    if (len > 0 && data) {
      ssize_t r = write(fd, data, len);
      (void)r;
    }
    close(fd);
  }
  fd = open(g_seq_path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
  if (fd >= 0) {
    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%lu%s\n", seq, (seq % 2 == 0) ? " " : "");
    ssize_t r = write(fd, buf, (size_t)n);
    (void)r;
    close(fd);
  }
}

/* ─────────────────────────────────────────────────────────────────────
   ensure_cache_dir()
   Resolve cache directory, populate path globals, create directory.

   Priority: explicit argument > $TMPDIR > /tmp
   Do NOT use XDG_RUNTIME_DIR (not set on macOS).
   Do NOT use /dev/shm (does not exist on macOS).
   Returns 0 on success, -1 on failure.
   ───────────────────────────────────────────────────────────────────── */
static int ensure_cache_dir(const char *dir) {
  if (dir && dir[0]) {
    snprintf(g_cache_dir, sizeof(g_cache_dir), "%s", dir);
  } else {
    const char *tmpdir = getenv("TMPDIR");
    if (tmpdir && tmpdir[0]) {
      snprintf(g_cache_dir, sizeof(g_cache_dir), "%s/zsh-edit-select-%d",
               tmpdir, (int)getuid());
    } else {
      snprintf(g_cache_dir, sizeof(g_cache_dir), "/tmp/zsh-edit-select-%d",
               (int)getuid());
    }
  }

  snprintf(g_primary_path, sizeof(g_primary_path), "%s/%s", g_cache_dir,
           PRIMARY_FILE);
  snprintf(g_seq_path, sizeof(g_seq_path), "%s/%s", g_cache_dir, SEQ_FILE);
  snprintf(g_pid_path, sizeof(g_pid_path), "%s/%s", g_cache_dir, PID_FILE);

  struct stat st; /* Correction J: MUST declare before stat() call */
  if (stat(g_cache_dir, &st) == -1) {
    if (mkdir(g_cache_dir, 0700) == -1 && errno != EEXIST)
      return -1;
  }
  return 0;
}

/* ─────────────────────────────────────────────────────────────────────
   ax_read_and_write_selection()
   Called on the main queue after every kCGEventLeftMouseUp event.

   Reads kAXSelectedTextAttribute from the focused UI element.
   If non-empty and different from the dedup cache: write to primary.
   If empty and cached was non-empty: write empty primary (cleared signal).
   If AX not supported (Kitty etc.): silently skip — NO Copy-on-Select.

   DEDUPLICATION: kCGEventLeftMouseUp fires on every click, including
   single clicks without a selection. Without dedup, every click would
   produce a spurious seq mtime change. We cache the last selection in
   g_last_ax_selection[4096] and skip writing if identical.

   Adaptive Fast-Path (is_retry param):
   We explicitly return false if kAXSelectedTextAttribute is empty but
   we are running in the fast path. This allows the caller to schedule a
   5ms retry to catch natively slow terminals (Terminal.app) that update
   async, while preserving <1ms latency for fast terminals.

   MUST be called from the main run loop thread (dispatch_get_main_queue()).
   REQUIRES: AXIsProcessTrusted() == YES (caller ensures this).
   ───────────────────────────────────────────────────────────────────── */
static void ax_read_and_write_selection(void) {
  @autoreleasepool {
    AXUIElementRef system_wide = AXUIElementCreateSystemWide();
    if (!system_wide) return; // Handled

    /* Get the focused UI element (terminal text area with keyboard focus). */
    AXUIElementRef focused = NULL;
    AXError err = AXUIElementCopyAttributeValue(
        system_wide, kAXFocusedUIElementAttribute, (CFTypeRef *)&focused);
    CFRelease(system_wide);

    if (err != kAXErrorSuccess || !focused) {
      /* No focused element (e.g. focus on desktop) or terminal hasn't updated. */
      if (g_last_ax_selection_len > 0) {
        g_last_ax_selection[0] = '\0';
        g_last_ax_selection_len = 0;
        g_seq_counter++;
        write_primary("", 0, g_seq_counter);
      }
      return; /* Handled */
    }

    /* Read the selected text from the focused element. */
    CFTypeRef value = NULL;
    err = AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute,
                                        &value);
    CFRelease(focused);

    if (err != kAXErrorSuccess || !value) {
      /* Terminal does not support kAXSelectedTextAttribute (Kitty,
         Alacritty, WezTerm, Ghostty) OR terminal hasn't updated model yet. */
      if (g_last_ax_selection_len > 0) {
        g_last_ax_selection[0] = '\0';
        g_last_ax_selection_len = 0;
        g_seq_counter++;
        write_primary("", 0, g_seq_counter);
      }
      return; /* Handled */
    }

    NSString *str = (__bridge_transfer NSString *)value;
    if (!str || str.length == 0) {
      /* Empty selection: user clicked without selecting. */
      if (g_last_ax_selection_len > 0) {
        g_last_ax_selection[0] = '\0';
        g_last_ax_selection_len = 0;
        g_seq_counter++;
        write_primary("", 0, g_seq_counter);
      }
      return; /* Handled */
    }

    const char *utf8 = [str UTF8String];
    if (!utf8)
      return;

    size_t len = strlen(utf8);
    if (len > MAX_CLIPBOARD_SIZE)
      len = MAX_CLIPBOARD_SIZE;

    /* Deduplication: skip write if identical to cached selection. */
    if (len == g_last_ax_selection_len && len > 0 &&
        len < AX_DEDUP_CACHE_SIZE && g_last_ax_selection[0] != '\0' &&
        memcmp(g_last_ax_selection, utf8, len) == 0) {
      return; /* Same selection — do not write (handled). */
    }

    /* Update deduplication cache. */
    if (len < AX_DEDUP_CACHE_SIZE) {
      memcpy(g_last_ax_selection, utf8, len);
      g_last_ax_selection[len] = '\0';
    } else {
      /* Too large to cache; disable dedup for this selection. */
      g_last_ax_selection[0] = '\0';
    }
    g_last_ax_selection_len = len;

    /* Write to primary cache. seq updated LAST (write order invariant). */
    g_seq_counter++;
    write_primary(utf8, len, g_seq_counter);

    return; /* Handled */
  }
}

/* ─────────────────────────────────────────────────────────────────────
   event_tap_callback()
   CGEventTap callback. Fires on kCGEventLeftMouseUp.

   Dispatches AX read to main queue via dispatch_async. This ensures the
   AX query runs on the main run loop thread as required, and also allows
   the target application to finalize its text selection model before
   we query it (~1µs enqueue overhead, imperceptible to users).

   kCGEventTapDisabledByTimeout / kCGEventTapDisabledByUserInput:
   macOS disables taps that block the event stream. Our tap is listen-only
   and completes in ~1µs — it will not time out. We re-enable as a safety
   measure in case the OS disables it anyway.

   IMPORTANT: This callback NEVER modifies or consumes events.
   It is purely a passive listener (kCGEventTapOptionListenOnly).
   ───────────────────────────────────────────────────────────────────── */
static CGEventRef event_tap_callback(CGEventTapProxy proxy, CGEventType type,
                                     CGEventRef event, void *refcon) {
  (void)proxy;
  (void)refcon;

  if (type == kCGEventTapDisabledByTimeout ||
      type == kCGEventTapDisabledByUserInput) {
    if (g_event_tap)
      CGEventTapEnable(g_event_tap, true);
    return event;
  }

  if (type == kCGEventLeftMouseUp && g_running) {
    /* Dispatch AX read to main queue with a 5ms delay.
       Terminal.app (and some other terminals) may update their AX text
       model slightly after kCGEventLeftMouseUp, causing
       kAXSelectedTextAttribute to return empty on immediate query.
       The 5ms delay is imperceptible (human reaction time ~150ms),
       but ensures the selection has settled. */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
                     if (g_running)
                       ax_read_and_write_selection();
                   });
  }

  return event;
}

/* ─────────────────────────────────────────────────────────────────────
   get_clipboard_utf8()
   Reads NSPasteboard as malloc'd UTF-8. Caller must free().
   Returns NULL if empty or on error. Sets *out_len to byte count.
   ───────────────────────────────────────────────────────────────────── */
static char *get_clipboard_utf8(size_t *out_len) {
  *out_len = 0;
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSString *str = [pb stringForType:NSPasteboardTypeString];
  if (!str)
    return NULL;

  const char *utf8 = [str UTF8String];
  if (!utf8)
    return NULL;

  size_t len = strlen(utf8);
  if (len == 0)
    return NULL;
  if (len > MAX_CLIPBOARD_SIZE)
    len = MAX_CLIPBOARD_SIZE;

  char *buf = malloc(len + 1);
  if (!buf)
    return NULL;
  memcpy(buf, utf8, len);
  buf[len] = '\0';
  *out_len = len;
  return buf;
}

/* ─────────────────────────────────────────────────────────────────────
   set_clipboard_utf8()
   Writes UTF-8 string to NSPasteboard. Returns true on success.
   The macOS pboard daemon owns clipboard storage — content persists
   after this process exits. No clipboard server child needed.
   ───────────────────────────────────────────────────────────────────── */
static bool set_clipboard_utf8(const char *data, size_t len) {
  if (!data || len == 0)
    return false;

  NSString *str = [[NSString alloc] initWithBytes:data
                                           length:len
                                         encoding:NSUTF8StringEncoding];
  if (!str) {
    str = [[NSString alloc] initWithBytes:data
                                   length:len
                                 encoding:NSISOLatin1StringEncoding];
  }
  if (!str)
    return false;

  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [pb clearContents];
  return [pb setString:str forType:NSPasteboardTypeString];
}

/* ─────────────────────────────────────────────────────────────────────
   read_all_stdin()
   Reads all stdin into malloc'd buffer. Caller must free().
   ───────────────────────────────────────────────────────────────────── */
static char *read_all_stdin(size_t *out_len) {
  size_t capacity = 4096, total = 0;
  char *buf = malloc(capacity);
  if (!buf) {
    *out_len = 0;
    return NULL;
  }

  while (1) {
    if (total + 4096 > capacity) {
      capacity *= 2;
      if (capacity > MAX_CLIPBOARD_SIZE)
        break;
      char *nb = realloc(buf, capacity);
      if (!nb) {
        free(buf);
        *out_len = 0;
        return NULL;
      }
      buf = nb;
    }
    ssize_t n = read(STDIN_FILENO, buf + total, 4096);
    if (n > 0)
      total += (size_t)n;
    else
      break;
  }
  *out_len = total;
  return buf;
}

/* ─────────────────────────────────────────────────────────────────────
   run_oneshot()
   Print clipboard text to stdout and exit.
   ───────────────────────────────────────────────────────────────────── */
static int run_oneshot(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    [[NSApplication sharedApplication]
        setActivationPolicy:NSApplicationActivationPolicyAccessory];

    size_t len = 0;
    char *data = get_clipboard_utf8(&len);
    if (data && len > 0) {
      fwrite(data, 1, len, stdout);
      free(data);
      return 0;
    }
    free(data);
    return 1;
  }
}

/* ─────────────────────────────────────────────────────────────────────
   run_copy_clipboard()
   Read stdin and write to NSPasteboard. No clipboard server needed —
   the macOS pboard daemon owns storage persistently after we write.
   ───────────────────────────────────────────────────────────────────── */
static int run_copy_clipboard(void) {
  size_t len = 0;
  char *data = read_all_stdin(&len);
  if (!data || len == 0) {
    free(data);
    return 1;
  }

  @autoreleasepool {
    [NSApplication sharedApplication];
    [[NSApplication sharedApplication]
        setActivationPolicy:NSApplicationActivationPolicyAccessory];

    bool ok = set_clipboard_utf8(data, len);
    free(data);
    return ok ? 0 : 1;
  }
}

/* ─────────────────────────────────────────────────────────────────────
   run_clear_primary()
   Clear local cache files so shell does not see stale text.
   DOES NOT call [NSPasteboard clearContents] — clearing the system
   clipboard would destroy user-copied content from other apps.
   Only the local seq/primary files (which the shell watches) are cleared.
   ───────────────────────────────────────────────────────────────────── */
static int run_clear_primary(void) {
  g_seq_counter++;
  write_primary("", 0, g_seq_counter);
  return 0;
}

/* ─────────────────────────────────────────────────────────────────────
   run_daemon_worker()
   The actual daemon process, launched via posix_spawn by run_daemon().
   Runs with a 100% clean process state.
   ───────────────────────────────────────────────────────────────────── */
static int run_daemon_worker(const char *cache_dir_arg) {
  if (ensure_cache_dir(cache_dir_arg) != 0) {
    return 1;
  }

  /* Child: new session, user namespace preserved. */
  setsid();

  /* ── COCOA INITIALIZATION ───────────────────────────────────────
     MUST happen here, AFTER fork(). Calling [NSApplication sharedApplication]
     before fork() leaves the child state corrupted (deadlocks and invalid
     Mach ports), crashing the daemon immediately. */
  @autoreleasepool {
    [NSApplication sharedApplication];
    [[NSApplication sharedApplication]
        setActivationPolicy:NSApplicationActivationPolicyAccessory];
  }

  {
    int devnull = open("/dev/null", O_RDWR | O_CLOEXEC);
    if (devnull >= 0) {
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
      if (devnull > STDERR_FILENO)
        close(devnull);
    }
  }

  /* Write PID file for shell liveness probes (kill -0 $pid). */
  {
    FILE *f = fopen(g_pid_path, "w");
    if (f) {
      fprintf(f, "%d\n", getpid());
      fclose(f);
    }
  }

  /* Open persistent fds for write_primary() hot path.
     O_CREAT ensures files exist if removed between write_primary()
     above and here.                                                   */
  g_fd_primary = open(g_primary_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);
  g_fd_seq = open(g_seq_path, O_WRONLY | O_CREAT | O_CLOEXEC, 0644);

  /* ── GCD signal handling ────────────────────────────────────────────
     MUST call signal(SIG, SIG_IGN) BEFORE creating dispatch sources
     for those signals. Otherwise the default handler fires on the
     first delivery, killing the process before the source is installed.
     GCD dispatch sources for signals run handlers on the specified queue
     (main queue here). Calling CFRunLoopStop() from main queue is safe. */
  signal(SIGTERM, SIG_IGN);
  signal(SIGINT, SIG_IGN);
  signal(SIGHUP, SIG_IGN);

  dispatch_source_t sig_term = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(sig_term, ^{
    g_running = 0;
    CFRunLoopStop(CFRunLoopGetMain());
  });
  dispatch_resume(sig_term);

  dispatch_source_t sig_int = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(sig_int, ^{
    g_running = 0;
    CFRunLoopStop(CFRunLoopGetMain());
  });
  dispatch_resume(sig_int);

  dispatch_source_t sig_hup = dispatch_source_create(
      DISPATCH_SOURCE_TYPE_SIGNAL, SIGHUP, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(sig_hup, ^{
    g_running = 0;
    CFRunLoopStop(CFRunLoopGetMain());
  });
  dispatch_resume(sig_hup);

  /* ── CGEventTap for AX-based PRIMARY selection ──────────────────────
     Installed ONLY if Accessibility permission is granted.
     Without it, the daemon runs but the primary cache is never updated
     by mouse actions — keyboard selections and paste still work.

     kCGSessionEventTap:     Session-level tap (sees all apps' events).
     kCGTailAppendEventTap:  Appended at end of event stream (passive).
     kCGEventTapOptionListenOnly: NEVER consume or modify events.
     CGEventMaskBit(kCGEventLeftMouseUp): only mouse button release.

     The tap run loop source is added to the main run loop.
     CFRunLoopRun() below pumps the main run loop.                      */
  if (AXIsProcessTrusted()) {
    CGEventMask mask = CGEventMaskBit(kCGEventLeftMouseUp);
    g_event_tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
                                   kCGEventTapOptionListenOnly, mask,
                                   event_tap_callback, NULL);

    if (g_event_tap) {
      g_tap_rls =
          CFMachPortCreateRunLoopSource(kCFAllocatorDefault, g_event_tap, 0);
      if (g_tap_rls) {
        CFRunLoopAddSource(CFRunLoopGetMain(), g_tap_rls,
                           kCFRunLoopDefaultMode);
        CGEventTapEnable(g_event_tap, true);
      }
    }
    /* If CGEventTapCreate fails (permission revoked after start),
       continue in no-AX mode silently.                               */
  }
  /* ───────────────────────────────────────────────────────────────── */

  /* Block main thread until GCD signal source calls CFRunLoopStop(). */
  CFRunLoopRun();

  /* ── Cleanup ────────────────────────────────────────────────────── */
  g_running = 0;

  dispatch_source_cancel(sig_term);
  dispatch_source_cancel(sig_int);
  dispatch_source_cancel(sig_hup);
  /* ARC manages dispatch_source_t lifetime. dispatch_release() is a
     compile error with -fobjc-arc and must NOT be called here.
     dispatch_source_cancel() above stops event delivery; ARC releases
     the objects when they go out of scope at function return.
     CFRelease() below is for CoreFoundation types — NOT affected by ARC,
     must be called explicitly.                                           */

  if (g_event_tap) {
    CGEventTapEnable(g_event_tap, false);
    if (g_tap_rls) {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), g_tap_rls,
                            kCFRunLoopDefaultMode);
      CFRelease(g_tap_rls);
      g_tap_rls = NULL;
    }
    CFRelease(g_event_tap);
    g_event_tap = NULL;
  }



  if (g_fd_primary >= 0) {
    close(g_fd_primary);
    g_fd_primary = -1;
  }
  if (g_fd_seq >= 0) {
    close(g_fd_seq);
    g_fd_seq = -1;
  }

  unlink(g_primary_path);
  unlink(g_seq_path);
  unlink(g_pid_path);
  return 0;
}

/* ─────────────────────────────────────────────────────────────────────
   run_daemon()
   Launcher for the daemon using posix_spawn.
   ───────────────────────────────────────────────────────────────────── */
static int run_daemon(const char *exe_path, const char *cache_dir_arg) {
  if (ensure_cache_dir(cache_dir_arg) != 0) {
    fprintf(stderr,
            "zes-macos-clipboard-agent: cannot create cache directory\n");
    return 1;
  }

  /* Seed counter monotonically larger than any prior daemon instance. */
  g_seq_counter = (unsigned long)time(NULL);

  /* Write readiness signal BEFORE spawn. Shell polls for this file.
     Uses fallback open/write/close path (g_fd_primary == -1 here). */
  write_primary("", 0, g_seq_counter);

  pid_t pid;
  const char *argv[] = {exe_path, "--_daemon-child", cache_dir_arg, NULL};

  posix_spawnattr_t attr;
  posix_spawnattr_init(&attr);

  /* macOS supports POSIX_SPAWN_SETSID to create a new session automatically */
#ifdef POSIX_SPAWN_SETSID
  posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);
#endif

  int ret =
      posix_spawn(&pid, exe_path, NULL, &attr, (char *const *)argv, environ);
  posix_spawnattr_destroy(&attr);

  if (ret != 0) {
    fprintf(stderr, "zes-macos-clipboard-agent: posix_spawn failed: %d\n", ret);
    return 1;
  }

  /* Launcher exits successfully. The spawned child runs the daemon worker. */
  return 0;
}

/* ─────────────────────────────────────────────────────────────────────
   main()
   Parse arguments and dispatch to the appropriate mode.

   COCOA INITIALIZATION:
   [NSApplication sharedApplication] MUST NOT be called before fork().
   It is called in the individual run_* functions (and after fork() in
   run_daemon).

   ACTIVATION POLICY (Correction P):
   setActivationPolicy:NSApplicationActivationPolicyAccessory MUST be called
   immediately after [NSApplication sharedApplication]. Without it, on macOS
   15 Sequoia, CGEventTapCreate silently returns NULL even when Accessibility
   permission is granted. NSApplicationActivationPolicyAccessory means: no
   Dock icon, no menu bar, but all system APIs (CGEventTap, AX) work correctly.

   SHORT-LIVED MODES that do not need NSPasteboard:
   --check-ax, --request-ax, --clear-primary are dispatched BEFORE the
   Cocoa initialization for minimal overhead.
   ───────────────────────────────────────────────────────────────────── */
int main(int argc, char *argv[]) {
  const char *cache_dir_arg = NULL;
  bool oneshot = false;
  bool get_clipboard = false;
  bool copy_clipboard = false;
  bool clear_primary = false;
  bool check_ax = false;
  bool request_ax = false;
  bool daemon_child = false;

  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--oneshot") == 0)
      oneshot = true;
    else if (strcmp(argv[i], "--get-clipboard") == 0)
      get_clipboard = true;
    else if (strcmp(argv[i], "--copy-clipboard") == 0)
      copy_clipboard = true;
    else if (strcmp(argv[i], "--clear-primary") == 0)
      clear_primary = true;
    else if (strcmp(argv[i], "--check-ax") == 0)
      check_ax = true;
    else if (strcmp(argv[i], "--request-ax") == 0)
      request_ax = true;
    else if (strcmp(argv[i], "--_daemon-child") == 0)
      daemon_child = true;
    else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
      fprintf(stderr,
              "Usage: %s [cache_dir] [--oneshot|--get-clipboard"
              "|--copy-clipboard|--clear-primary|--check-ax|--request-ax]\n"
              "macOS AX-based primary selection agent for zsh-edit-select.\n\n"
              "  (default)          Daemon: CGEventTap+AX for mouse selection\n"
              "  --oneshot          Print current clipboard and exit\n"
              "  --get-clipboard    Alias for --oneshot\n"
              "  --copy-clipboard   Read stdin, set as clipboard, exit\n"
              "  --clear-primary    Clear local cache files only (NOT "
              "NSPasteboard)\n"
              "  --check-ax         Exit 0 if Accessibility permission "
              "granted, 1 if not\n"
              "  --request-ax       Prompt for Accessibility permission; exit "
              "0 if granted\n",
              argv[0]);
      return 0;
    } else {
      cache_dir_arg = argv[i];
    }
  }

  /* --check-ax: no NSPasteboard needed. */
  if (check_ax) {
    return AXIsProcessTrusted() ? 0 : 1;
  }

  /* --request-ax: no NSPasteboard needed. */
  if (request_ax) {
    @autoreleasepool {
      NSDictionary *opts = @{(__bridge id)kAXTrustedCheckOptionPrompt : @YES};
      bool trusted =
          AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
      return trusted ? 0 : 1;
    }
  }

  /* --clear-primary: touches only local files, no NSPasteboard needed.
     Read current seq from file to ensure the clear write has a seq
     value higher than the daemon's last write, preventing a stale
     mtime from being missed by the shell.
     g_seq_counter is _Atomic; use unsigned long tmp for fscanf
     (passing &g_seq_counter to %lu is undefined behavior).           */
  if (clear_primary) {
    if (ensure_cache_dir(cache_dir_arg) != 0)
      return 1;
    FILE *f = fopen(g_seq_path, "r");
    if (f) {
      unsigned long tmp = 0;
      if (fscanf(f, "%lu", &tmp) == 1)
        g_seq_counter = tmp;
      else
        g_seq_counter = (unsigned long)time(NULL);
      fclose(f);
    } else {
      g_seq_counter = (unsigned long)time(NULL);
    }
    return run_clear_primary();
  }

  /* All remaining modes require NSPasteboard.
     Cocoa runtime initialization is deferred and handled by each
     mode individually to ensure it happens AFTER fork() for the daemon. */

  if (oneshot || get_clipboard)
    return run_oneshot();
  if (copy_clipboard)
    return run_copy_clipboard();
  if (daemon_child)
    return run_daemon_worker(cache_dir_arg);

  /* Default: daemon mode. */
  return run_daemon(argv[0], cache_dir_arg);
}
