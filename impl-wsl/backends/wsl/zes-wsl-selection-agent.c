// Copyright (c) 2025 Michael Matta
// Version: 0.6.4
// Homepage: https://github.com/Michael-Matta1/zsh-edit-select
//
// Linux-side clipboard agent for zsh-edit-select WSL backend.
// Communicates with zes-wsl-clipboard-helper.exe (Windows side) via pipes.
//
// Compile: gcc -O3 zes-wsl-selection-agent.c -o zes-wsl-selection-agent
// Usage:   zes-wsl-selection-agent [cache_dir] [--oneshot|--get-clipboard|--copy-clipboard|--clear-primary]
//
// In daemon mode the agent launches the Windows helper (.exe) with --daemon,
// reads its stdout protocol, and writes cache files using the same
// pwrite+ftruncate protocol as the X11 and Wayland agents.  Cache files
// sit on native Linux tmpfs for fast zstat from the shell.

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <time.h>
#include <stdbool.h>
#include <limits.h>

/* Cache-directory filenames and safety cap.
   PRIMARY_FILE / SEQ_FILE: selected text and change counter.
   PID_FILE: daemon PID for liveness checks.
   MAX_CLIPBOARD_SIZE: 4 MB cap on clipboard reads. */
#define PRIMARY_FILE "primary"
#define SEQ_FILE "seq"
#define PID_FILE "agent.pid"
#define MAX_CLIPBOARD_SIZE (4 * 1024 * 1024)

/* Name of the Windows helper binary (same directory as this agent). */
#define HELPER_NAME "zes-wsl-clipboard-helper.exe"

static volatile sig_atomic_t running = 1;
static char cache_dir[512];
static char primary_path[560];
static char seq_path[560];
static char pid_path[560];
static char helper_path[560];

/* Monotonically increasing counter written to SEQ_FILE; the shell polls
   its mtime to detect selection changes without reading content. */
static unsigned long seq_counter = 0;

/* Persistent fds for write_primary() daemon hot path.
   Opened once after daemon() in run_daemon(); reused for all subsequent writes.
   -1 = not yet open (pre-daemon initial write uses the open/write/close fallback). */
static int fd_primary = -1;
static int fd_seq     = -1;

/* PID of the Windows helper child (daemon mode). */
static pid_t helper_pid = -1;

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
           1. XDG_RUNTIME_DIR/<uid> — tmpfs, survives logout cleanup by PAM.
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

/* Resolve the helper .exe path relative to this agent binary.
   argv0 is used to determine the directory. */
static int resolve_helper_path(const char *argv0) {
    /* Try /proc/self/exe first for a reliable absolute path. */
    char self[512];
    ssize_t n = readlink("/proc/self/exe", self, sizeof(self) - 1);
    const char *dir_src = NULL;

    if (n > 0) {
        self[n] = '\0';
        dir_src = self;
    } else if (argv0) {
        dir_src = argv0;
    } else {
        return -1;
    }

    /* Find the last '/' and build the helper path. */
    const char *slash = strrchr(dir_src, '/');
    if (slash) {
        size_t dirlen = (size_t)(slash - dir_src);
        if (dirlen + 1 + strlen(HELPER_NAME) >= sizeof(helper_path))
            return -1;
        memcpy(helper_path, dir_src, dirlen);
        helper_path[dirlen] = '/';
        strcpy(helper_path + dirlen + 1, HELPER_NAME);
    } else {
        snprintf(helper_path, sizeof(helper_path), "./%s", HELPER_NAME);
    }

    return access(helper_path, X_OK) == 0 ? 0 : -1;
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
        int sn = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = pwrite(fd_seq, buf, (size_t)sn, 0);
        (void)r;
        (void)ftruncate(fd_seq, (off_t)sn);
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
        int sn = snprintf(buf, sizeof(buf), "%lu\n", seq);
        ssize_t r = write(fd, buf, sn);
        (void)r;
        close(fd);
    }
}

/* ------------------------------------------------------------------ */
/*  Helper communication: launch and read protocol.                   */
/* ------------------------------------------------------------------ */

/* Launch the Windows helper with the given arguments.  Returns fd for
   reading the helper's stdout, or -1 on error.  Sets helper_pid. */
static int launch_helper(const char *mode) {
    int pipefd[2];
    if (pipe(pipefd) < 0)
        return -1;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        /* Child: redirect stdout to pipe, exec the helper. */
        close(pipefd[0]);
        if (pipefd[1] != STDOUT_FILENO) {
            dup2(pipefd[1], STDOUT_FILENO);
            close(pipefd[1]);
        }
        /* Close stderr in daemon child to avoid noise. */
        int devnull = open("/dev/null", O_WRONLY | O_CLOEXEC);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execl(helper_path, helper_path, mode, (char *)NULL);
        _exit(127);
    }

    /* Parent. */
    close(pipefd[1]);
    helper_pid = pid;
    return pipefd[0];
}

/* Launch the Windows helper with stdin piped FROM us.  Used by
   --copy-clipboard: pipe data to the helper's stdin.
   Returns the write-end fd, or -1 on error. */
static int launch_helper_with_stdin(const char *mode) {
    int pipefd[2];
    if (pipe(pipefd) < 0)
        return -1;

    pid_t pid = fork();
    if (pid < 0) {
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        /* Child: redirect stdin from pipe. */
        close(pipefd[1]);
        if (pipefd[0] != STDIN_FILENO) {
            dup2(pipefd[0], STDIN_FILENO);
            close(pipefd[0]);
        }
        /* Silence stderr. */
        int devnull = open("/dev/null", O_WRONLY | O_CLOEXEC);
        if (devnull >= 0) {
            dup2(devnull, STDERR_FILENO);
            close(devnull);
        }
        execl(helper_path, helper_path, mode, (char *)NULL);
        _exit(127);
    }

    /* Parent: write end. */
    close(pipefd[0]);
    return pipefd[1];
}

/* Read a line from fd into buf (max bufsize-1 chars).
   Returns the number of bytes read (excluding NUL), or -1 on error/EOF.
   Does NOT include the trailing '\n' in buf. */
static int read_line(int fd, char *buf, size_t bufsize) {
    size_t pos = 0;
    while (pos < bufsize - 1) {
        char c;
        ssize_t n = read(fd, &c, 1);
        if (n <= 0)
            return -1;
        if (c == '\n') {
            buf[pos] = '\0';
            return (int)pos;
        }
        buf[pos++] = c;
    }
    buf[pos] = '\0';
    return (int)pos;
}

/* Read exactly `len` bytes from fd into buf.  Returns 0 on success. */
static int read_exact(int fd, char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t n = read(fd, buf + off, len - off);
        if (n <= 0)
            return -1;
        off += (size_t)n;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/*  --oneshot / --get-clipboard: run helper, relay output.            */
/* ------------------------------------------------------------------ */
static int run_oneshot(void) {
    int fd = launch_helper("--get-clipboard");
    if (fd < 0) {
        /* Fallback to powershell.exe */
        execlp("powershell.exe", "powershell.exe",
               "-NoProfile", "-Command", "Get-Clipboard", (char *)NULL);
        return 1;
    }

    char buf[4096];
    ssize_t n;
    int wrote = 0;
    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        fwrite(buf, 1, (size_t)n, stdout);
        wrote = 1;
    }
    close(fd);

    int status;
    waitpid(helper_pid, &status, 0);
    return wrote ? 0 : 1;
}

static int run_get_clipboard(void) {
    return run_oneshot();
}

/* ------------------------------------------------------------------ */
/*  --copy-clipboard: pipe stdin to helper --set-clipboard.           */
/* ------------------------------------------------------------------ */
static int run_copy_clipboard(void) {
    int wfd = launch_helper_with_stdin("--set-clipboard");
    if (wfd < 0) {
        /* Fallback to clip.exe */
        execlp("clip.exe", "clip.exe", (char *)NULL);
        return 1;
    }

    char buf[4096];
    ssize_t n;
    while ((n = read(STDIN_FILENO, buf, sizeof(buf))) > 0) {
        size_t off = 0;
        while (off < (size_t)n) {
            ssize_t w = write(wfd, buf + off, (size_t)n - off);
            if (w <= 0) goto done;
            off += (size_t)w;
        }
    }
done:
    close(wfd);

    int status;
    waitpid(helper_pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}

/* ------------------------------------------------------------------ */
/*  --clear-primary: clear cache files (no Windows-side operation).   */
/*  Windows has no PRIMARY selection; we only clear the local cache   */
/*  so the shell does not see stale text.                             */
/* ------------------------------------------------------------------ */
static int run_clear_primary(void) {
    if (ensure_cache_dir(NULL) != 0) return 1;

    /* Read current seq counter from file and increment. */
    FILE *f = fopen(seq_path, "r");
    if (f) {
        if (fscanf(f, "%lu", &seq_counter) != 1)
            seq_counter = (unsigned long)time(NULL);
        fclose(f);
    } else {
        seq_counter = (unsigned long)time(NULL);
    }
    seq_counter++;
    write_primary("", 0, seq_counter);
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Daemon mode: launch helper --daemon, read protocol, write cache.  */
/* ------------------------------------------------------------------ */
static int run_daemon(const char *cache_dir_arg) {
    if (ensure_cache_dir(cache_dir_arg) != 0) {
        fprintf(stderr, "Cannot create cache directory\n");
        return 1;
    }

    /* Write empty cache files before daemonising so the shell never tries
       to read a non-existent file during the startup window.
       seq is seeded to time(NULL) so it is monotonically increasing across
       daemon restarts, preventing false positive change detections. */
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

    /* Launch the Windows helper in --daemon mode. */
    int pipe_fd = launch_helper("--daemon");
    if (pipe_fd < 0) {
        fprintf(stderr, "Failed to launch Windows helper\n");
        goto cleanup;
    }

    /* Wait for the READY signal from the helper. */
    {
        char line[256];
        int len = read_line(pipe_fd, line, sizeof(line));
        if (len < 0 || strncmp(line, "READY", 5) != 0) {
            fprintf(stderr, "Helper did not send READY\n");
            close(pipe_fd);
            goto cleanup;
        }
    }

    /* Event loop: poll on the helper's stdout pipe.
       The helper sends CLIPBOARD/EMPTY/HEARTBEAT messages.
       We write cache files on each clipboard change. */
    while (running) {
        struct pollfd pfd = { .fd = pipe_fd, .events = POLLIN };
        int ret = poll(&pfd, 1, 10000);  /* 10s timeout for signal check */

        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }

        if (ret == 0)
            continue;  /* Timeout — check running flag. */

        if (pfd.revents & (POLLHUP | POLLERR)) {
            /* Helper died or pipe broke. */
            break;
        }

        if (pfd.revents & POLLIN) {
            char line[256];
            int len = read_line(pipe_fd, line, sizeof(line));
            if (len < 0) break;  /* EOF or error — helper died. */

            if (strncmp(line, "CLIPBOARD ", 10) == 0) {
                /* Parse: CLIPBOARD <seq> <content_len> */
                unsigned long win_seq;
                size_t content_len;
                if (sscanf(line + 10, "%lu %zu", &win_seq, &content_len) != 2)
                    continue;

                if (content_len > MAX_CLIPBOARD_SIZE)
                    content_len = MAX_CLIPBOARD_SIZE;

                char *content = NULL;
                if (content_len > 0) {
                    content = (char *)malloc(content_len + 1);
                    if (!content) continue;
                    if (read_exact(pipe_fd, content, content_len) != 0) {
                        free(content);
                        break;
                    }
                    content[content_len] = '\0';
                }

                /* Always increment seq even when content is identical — a
                   reselect of exactly the same text must still trigger a
                   fresh event in the shell. */
                seq_counter++;
                write_primary(content ? content : "", content_len, seq_counter);
                free(content);

            } else if (strncmp(line, "EMPTY ", 6) == 0) {
                seq_counter++;
                write_primary("", 0, seq_counter);

            } else if (strncmp(line, "HEARTBEAT", 9) == 0) {
                /* Liveness signal — nothing to do. */
                continue;
            }
            /* Unknown lines are silently ignored for forward compatibility. */
        }
    }

    close(pipe_fd);

    /* Kill the Windows helper child if it is still running. */
    if (helper_pid > 0) {
        kill(helper_pid, SIGTERM);
        waitpid(helper_pid, NULL, WNOHANG);
    }

cleanup:
    if (fd_primary >= 0) { close(fd_primary); fd_primary = -1; }
    if (fd_seq     >= 0) { close(fd_seq);     fd_seq     = -1; }
    unlink(primary_path);
    unlink(seq_path);
    unlink(pid_path);
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Entry point — parse argv and dispatch.                            */
/*                                                                    */
/*  Modes (first matching flag wins):                                 */
/*    (default)          Daemon: monitor clipboard via Windows helper  */
/*                       and write changes to cache files.             */
/*    --oneshot          Print current clipboard text and exit.        */
/*    --get-clipboard    Print clipboard text and exit (alias).        */
/*    --copy-clipboard   Read stdin, set as clipboard.                 */
/*    --clear-primary    Clear the cache files.                        */
/*    --help / -h        Print usage.                                  */
/* ------------------------------------------------------------------ */
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
                "WSL clipboard agent for zsh-edit-select.\n\n"
                "  (default)         Daemon mode — monitor Windows clipboard\n"
                "  --oneshot         Print current clipboard and exit\n"
                "  --get-clipboard   Print clipboard contents and exit\n"
                "  --copy-clipboard  Read stdin, set as clipboard\n"
                "  --clear-primary   Clear cache files\n",
                argv[0]);
            return 0;
        } else {
            cache_dir_arg = argv[i];
        }
    }

    /* Resolve the helper .exe path before dispatching. */
    if (resolve_helper_path(argv[0]) != 0) {
        /* Helper not found — short-lived modes can still fall back to
           powershell.exe / clip.exe inside their respective functions. */
        if (!clear_primary && !oneshot && !get_clipboard && !copy_clipboard) {
            fprintf(stderr, "Cannot find %s alongside this binary\n", HELPER_NAME);
            return 1;
        }
    }

    if (oneshot)
        return run_oneshot();
    if (get_clipboard)
        return run_get_clipboard();
    if (copy_clipboard)
        return run_copy_clipboard();
    if (clear_primary) {
        if (cache_dir_arg)
            ensure_cache_dir(cache_dir_arg);
        return run_clear_primary();
    }

    return run_daemon(cache_dir_arg);
}
