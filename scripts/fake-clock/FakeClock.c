// Moves a simulator app's wall clock to HOMEPAD_FAKE_CLOCK (seconds since 1970),
// so README screenshots show the same daytime moment whenever they are taken.
// Loaded with DYLD_INSERT_LIBRARIES (see scripts/readme_images.py). The clock
// keeps running from that moment: only the wall clock moves, never the
// monotonic one, so timers and animations behave as usual.
#include <stdint.h>
#include <stdlib.h>
#include <sys/time.h>
#include <time.h>

static int64_t offset_ns;

__attribute__((constructor)) static void start(void) {
    const char *target = getenv("HOMEPAD_FAKE_CLOCK");
    if (target == NULL) return;
    // Calls from this library are never interposed, so this is the real time.
    uint64_t now = clock_gettime_nsec_np(CLOCK_REALTIME);
    offset_ns = (int64_t)(atof(target) * 1e9) - (int64_t)now;
}

static void shift(struct timespec *ts) {
    int64_t ns = (int64_t)ts->tv_sec * 1000000000 + ts->tv_nsec + offset_ns;
    ts->tv_sec = (time_t)(ns / 1000000000);
    ts->tv_nsec = (long)(ns % 1000000000);
}

static int fake_clock_gettime(clockid_t clock, struct timespec *ts) {
    int result = clock_gettime(clock, ts);
    if (result == 0 && ts != NULL && clock == CLOCK_REALTIME) shift(ts);
    return result;
}

static uint64_t fake_clock_gettime_nsec_np(clockid_t clock) {
    uint64_t ns = clock_gettime_nsec_np(clock);
    return clock == CLOCK_REALTIME && ns != 0 ? (uint64_t)((int64_t)ns + offset_ns) : ns;
}

static int fake_gettimeofday(struct timeval *tv, void *zone) {
    int result = gettimeofday(tv, zone);
    if (result == 0 && tv != NULL) {
        struct timespec ts = {tv->tv_sec, (long)tv->tv_usec * 1000};
        shift(&ts);
        tv->tv_sec = ts.tv_sec;
        tv->tv_usec = (suseconds_t)(ts.tv_nsec / 1000);
    }
    return result;
}

static time_t fake_time(time_t *out) {
    time_t now = (time_t)((int64_t)time(NULL) + offset_ns / 1000000000);
    if (out != NULL) *out = now;
    return now;
}

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *with; const void *replaces; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = \
    {(const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&original};

INTERPOSE(fake_clock_gettime, clock_gettime)
INTERPOSE(fake_clock_gettime_nsec_np, clock_gettime_nsec_np)
INTERPOSE(fake_gettimeofday, gettimeofday)
INTERPOSE(fake_time, time)
