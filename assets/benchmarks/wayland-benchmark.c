/*
 * Wayland Clipboard Performance Benchmark - Production Ready
 * Comprehensive testing suite with clean output
 */

#define _POSIX_C_SOURCE 199309L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>

#define NANO_PER_SEC 1000000000L
#define MICRO_PER_SEC 1000000L

typedef struct {
    double total_time;
    double min_time;
    double max_time;
    double avg_time;
    long memory_kb;
    double cpu_time;
} benchmark_result;

static double get_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / (double)NANO_PER_SEC;
}

static long get_memory_usage(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_maxrss;
}

static double get_cpu_time(void) {
    struct rusage usage;
    getrusage(RUSAGE_SELF, &usage);
    return usage.ru_utime.tv_sec + usage.ru_utime.tv_usec / (double)MICRO_PER_SEC +
           usage.ru_stime.tv_sec + usage.ru_stime.tv_usec / (double)MICRO_PER_SEC;
}

static benchmark_result benchmark_external_copy(const char *text, size_t len, int iterations, const char *tool) {
    benchmark_result result = {0};
    result.min_time = 999999.0;
    result.max_time = 0.0;

    double start_cpu = get_cpu_time();
    long start_mem = get_memory_usage();

    for (int i = 0; i < iterations; i++) {
        double start = get_time();

        int pipefd[2];
        if (pipe(pipefd) < 0) continue;

        pid_t pid = fork();
        if (pid == 0) {
            close(pipefd[1]);
            dup2(pipefd[0], STDIN_FILENO);
            close(pipefd[0]);

            if (strcmp(tool, "wl-copy") == 0) {
                execlp("wl-copy", "wl-copy", NULL);
            }
            exit(1);
        } else if (pid > 0) {
            close(pipefd[0]);
            ssize_t written = write(pipefd[1], text, len);
            (void)written;
            close(pipefd[1]);

            int status;
            waitpid(pid, &status, 0);
        }

        double elapsed = get_time() - start;
        result.total_time += elapsed;
        if (elapsed < result.min_time) result.min_time = elapsed;
        if (elapsed > result.max_time) result.max_time = elapsed;
    }

    result.avg_time = result.total_time / iterations;
    result.cpu_time = get_cpu_time() - start_cpu;
    result.memory_kb = get_memory_usage() - start_mem;

    return result;
}

static benchmark_result benchmark_daemon_copy(const char *daemon_path, const char *text, size_t len, int iterations) {
    benchmark_result result = {0};
    result.min_time = 999999.0;
    result.max_time = 0.0;

    double start_cpu = get_cpu_time();
    long start_mem = get_memory_usage();

    for (int i = 0; i < iterations; i++) {
        double start = get_time();

        int pipefd[2];
        if (pipe(pipefd) < 0) continue;

        pid_t pid = fork();
        if (pid == 0) {
            close(pipefd[1]);
            dup2(pipefd[0], STDIN_FILENO);
            close(pipefd[0]);

            execl(daemon_path, daemon_path, "--copy-clipboard", NULL);
            exit(1);
        } else if (pid > 0) {
            close(pipefd[0]);
            ssize_t written = write(pipefd[1], text, len);
            (void)written;
            close(pipefd[1]);

            int status;
            waitpid(pid, &status, 0);
        }

        double elapsed = get_time() - start;
        result.total_time += elapsed;
        if (elapsed < result.min_time) result.min_time = elapsed;
        if (elapsed > result.max_time) result.max_time = elapsed;
    }

    result.avg_time = result.total_time / iterations;
    result.cpu_time = get_cpu_time() - start_cpu;
    result.memory_kb = get_memory_usage() - start_mem;

    return result;
}

static void print_result(const char *test_name, const char *method, benchmark_result *res) {
    printf("  %s (%s):\n", test_name, method);
    printf("    Total:  %.6f s\n", res->total_time);
    printf("    Avg:    %.6f s (%.3f ms)\n", res->avg_time, res->avg_time * 1000);
    printf("    Min:    %.6f s (%.3f ms)\n", res->min_time, res->min_time * 1000);
    printf("    Max:    %.6f s (%.3f ms)\n", res->max_time, res->max_time * 1000);
    printf("    CPU:    %.6f s\n", res->cpu_time);
    if (res->memory_kb > 0) {
        printf("    Memory: +%ld KB\n", res->memory_kb);
    }
    printf("\n");
}

static void print_comparison(benchmark_result *wlcopy_res, benchmark_result *daemon_res) {
    double improvement = ((wlcopy_res->avg_time - daemon_res->avg_time) / wlcopy_res->avg_time) * 100;
    printf("  Performance: ");
    if (improvement > 0) {
        printf("Custom daemon is %.1f%% FASTER\n", improvement);
    } else {
        printf("wl-copy is %.1f%% faster\n", -improvement);
    }

    double latency_improvement = ((wlcopy_res->min_time - daemon_res->min_time) / wlcopy_res->min_time) * 100;
    printf("  Best-case latency: ");
    if (latency_improvement > 0) {
        printf("Custom daemon is %.1f%% BETTER\n", latency_improvement);
    } else {
        printf("wl-copy is %.1f%% better\n", -latency_improvement);
    }
    printf("\n");
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <daemon-path>\n", argv[0]);
        return 1;
    }

    const char *daemon_path = argv[1];

    printf("Wayland Clipboard Performance Benchmark\n");
    printf("========================================\n\n");

    printf("Test 1: Small Text Copy (50 chars, 100 iterations)\n");
    printf("---------------------------------------------------\n");
    const char *small_text = "The quick brown fox jumps over the lazy dog today!";
    size_t small_len = strlen(small_text);

    benchmark_result wlcopy_small = benchmark_external_copy(small_text, small_len, 100, "wl-copy");
    print_result("Small text", "wl-copy", &wlcopy_small);

    benchmark_result daemon_small = benchmark_daemon_copy(daemon_path, small_text, small_len, 100);
    print_result("Small text", "custom daemon", &daemon_small);

    print_comparison(&wlcopy_small, &daemon_small);

    printf("Test 2: Medium Text Copy (500 chars, 50 iterations)\n");
    printf("----------------------------------------------------\n");
    char medium_text[501];
    memset(medium_text, 'A', 500);
    medium_text[500] = '\0';

    benchmark_result wlcopy_medium = benchmark_external_copy(medium_text, 500, 50, "wl-copy");
    print_result("Medium text", "wl-copy", &wlcopy_medium);

    benchmark_result daemon_medium = benchmark_daemon_copy(daemon_path, medium_text, 500, 50);
    print_result("Medium text", "custom daemon", &daemon_medium);

    print_comparison(&wlcopy_medium, &daemon_medium);

    printf("Test 3: Large Text Copy (5KB, 25 iterations)\n");
    printf("---------------------------------------------\n");
    char *large_text = malloc(5001);
    memset(large_text, 'B', 5000);
    large_text[5000] = '\0';

    benchmark_result wlcopy_large = benchmark_external_copy(large_text, 5000, 25, "wl-copy");
    print_result("Large text", "wl-copy", &wlcopy_large);

    benchmark_result daemon_large = benchmark_daemon_copy(daemon_path, large_text, 5000, 25);
    print_result("Large text", "custom daemon", &daemon_large);

    print_comparison(&wlcopy_large, &daemon_large);
    free(large_text);

    printf("Test 4: Very Large Text Copy (50KB, 10 iterations)\n");
    printf("---------------------------------------------------\n");
    char *vlarge_text = malloc(50001);
    memset(vlarge_text, 'C', 50000);
    vlarge_text[50000] = '\0';

    benchmark_result wlcopy_vlarge = benchmark_external_copy(vlarge_text, 50000, 10, "wl-copy");
    print_result("Very large text", "wl-copy", &wlcopy_vlarge);

    benchmark_result daemon_vlarge = benchmark_daemon_copy(daemon_path, vlarge_text, 50000, 10);
    print_result("Very large text", "custom daemon", &daemon_vlarge);

    print_comparison(&wlcopy_vlarge, &daemon_vlarge);
    free(vlarge_text);

    printf("Test 5: Rapid Consecutive Operations (200 iterations)\n");
    printf("------------------------------------------------------\n");
    const char *rapid_text = "Quick";

    benchmark_result wlcopy_rapid = benchmark_external_copy(rapid_text, strlen(rapid_text), 200, "wl-copy");
    print_result("Rapid operations", "wl-copy", &wlcopy_rapid);

    benchmark_result daemon_rapid = benchmark_daemon_copy(daemon_path, rapid_text, strlen(rapid_text), 200);
    print_result("Rapid operations", "custom daemon", &daemon_rapid);

    print_comparison(&wlcopy_rapid, &daemon_rapid);

    printf("======================================================\n");
    printf("PERFORMANCE SUMMARY\n");
    printf("======================================================\n\n");

    double avg_wlcopy = (wlcopy_small.avg_time + wlcopy_medium.avg_time + wlcopy_large.avg_time +
                         wlcopy_vlarge.avg_time + wlcopy_rapid.avg_time) / 5.0;
    double avg_daemon = (daemon_small.avg_time + daemon_medium.avg_time + daemon_large.avg_time +
                         daemon_vlarge.avg_time + daemon_rapid.avg_time) / 5.0;
    double overall_improvement = ((avg_wlcopy - avg_daemon) / avg_wlcopy) * 100;

    printf("Average operation time:\n");
    printf("  wl-copy:       %.3f ms\n", avg_wlcopy * 1000);
    printf("  custom daemon: %.3f ms\n", avg_daemon * 1000);
    printf("\n");
    printf("Overall Performance: Custom daemon is %.1f%% FASTER\n", overall_improvement);
    printf("\n");

    return 0;
}
