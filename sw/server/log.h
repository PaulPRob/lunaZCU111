/* log.h - minimal logging to stderr (captured by syslog/journald) */
#ifndef LOG_H
#define LOG_H

#include <stdio.h>
#include <time.h>

extern int g_verbose;

#define LOG_AT(tag, ...)                                                   \
    do {                                                                   \
        struct timespec ts_;                                               \
        clock_gettime(CLOCK_REALTIME, &ts_);                               \
        struct tm tm_;                                                     \
        localtime_r(&ts_.tv_sec, &tm_);                                    \
        fprintf(stderr, "%02d:%02d:%02d.%03ld %s ", tm_.tm_hour,          \
                tm_.tm_min, tm_.tm_sec, ts_.tv_nsec / 1000000, tag);       \
        fprintf(stderr, __VA_ARGS__);                                      \
        fputc('\n', stderr);                                               \
    } while (0)

#define LOGE(...)  LOG_AT("ERROR", __VA_ARGS__)
#define LOGW(...) LOG_AT("WARN ", __VA_ARGS__)
#define LOGI(...) LOG_AT("INFO ", __VA_ARGS__)
#define LOGD(...)  do { if (g_verbose) LOG_AT("DEBUG", __VA_ARGS__); } while (0)

#endif
