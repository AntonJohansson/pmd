#include "profile_linux.h"

#include <bits/time.h>
#include <time.h>
#include <x86intrin.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/mman.h>
#include <stdint.h>
#include <assert.h>

#include <asm/unistd.h>
#include <linux/perf_event.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <inttypes.h>

#define OS_TIMER_FREQ 1000000000

static uint64_t read_os_timer_ns(void) {
    struct timespec t;
    assert(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
    return OS_TIMER_FREQ*t.tv_sec + t.tv_nsec;
}

uint64_t read_os_pagefault_count(void) {
    struct rusage usage = {0};
    assert(getrusage(RUSAGE_SELF, &usage) == 0);
    return usage.ru_minflt + usage.ru_majflt;
}

uint64_t read_cpu_timer(void) {
    return __rdtsc();
}

// thank you ciro
static long perf_event_open(struct perf_event_attr *hw_event, pid_t pid,
                            int cpu, int group_fd, unsigned long flags)
{
    int ret;

    ret = syscall(__NR_perf_event_open, hw_event, pid, cpu,
                    group_fd, flags);
    return ret;
}

uint64_t estimate_cpu_timer_freq(void) {
    uint64_t ms_to_wait = 100;
    uint64_t os_freq = OS_TIMER_FREQ;

    uint64_t cpu_start = read_cpu_timer();
    uint64_t os_start = read_os_timer_ns();
    uint64_t os_end = 0;
    uint64_t os_elapsed = 0;
    uint64_t os_wait_time = os_freq * ms_to_wait / 1000;
    while (os_elapsed < os_wait_time)
    {
        os_end = read_os_timer_ns();
        os_elapsed = os_end - os_start;
    }

    uint64_t cpu_end = read_cpu_timer();
    uint64_t cpu_elapsed = cpu_end - cpu_start;

    uint64_t cpu_freq = 0;
    if (os_elapsed)
    {
        cpu_freq = os_freq * cpu_elapsed / os_elapsed;
    }

    return cpu_freq;
}

#ifndef PROFILE_ENABLE
#define PROFILE_ENABLE 1
#endif

#ifndef PROFILE_FAULTS
#define PROFILE_FAULTS 0
#endif

#ifndef PROFILE_L1_MISS
#define PROFILE_L1_MISS 0
#endif

#ifndef PROFILE_TLB
#define PROFILE_TLB 0
#endif

#if PROFILE_L1_MISS && PROFILE_TLB
# define CACHE_TYPE PERF_COUNT_HW_CACHE_DTLB
#else
# define CACHE_TYPE PERF_COUNT_HW_CACHE_L1D
#endif

//struct ProfileAnchor
//{
//    uint64_t tsc_elapsed_exclusive;
//    uint64_t tsc_elapsed_inclusive;
//    uint64_t pagefault_count_exclusive;
//    uint64_t pagefault_count_inclusive;
//    uint64_t cache_miss_count_exclusive;
//    uint64_t cache_miss_count_inclusive;
//    uint64_t hit_count;
//    uint64_t processed_byte_count;
//    char const *label;
//};
//
//struct ProfileBlock
//{
//    uint64_t old_tsc_elapsed_inclusive;
//    uint64_t old_pagefault_count_inclusive;
//    uint64_t old_cache_miss_count_inclusive;
//    uint64_t start_tsc;
//    uint64_t start_page_fault_count;
//    uint64_t start_cache_miss_count;
//    uint32_t parent_index;
//    uint32_t anchor_index;
//    char const *label;
//};

//struct ProfileBlock profile_block_begin(char const *label,
//                                        struct ProfileAnchor *anchor,
//                                        uint32_t anchor_index,
//                                        uint32_t parent_index,
//                                        uint64_t bytecount) {
//    struct ProfileBlock block = {0};
//    block.parent_index = parent_index;
//    block.anchor_index = anchor_index;
//    block.label = label;
//    block.old_tsc_elapsed_inclusive = anchor->tsc_elapsed_inclusive;
//    block.old_pagefault_count_inclusive = anchor->pagefault_count_inclusive;
//    block.old_cache_miss_count_inclusive = anchor->cache_miss_count_inclusive;
//    anchor->processed_byte_count += bytecount;
//
//#if PROFILE_FAULTS
//    block.start_pagefault_count = read_os_pagefault_count();
//#endif
//#if PROFILE_L1_MISS
//    block.start_cache_miss_count = read_cache_miss();
//#endif
//
//    block.start_tsc = read_cpu_timer();
//}
//
//void profile_block_end(struct ProfileBlock *block,
//                       struct ProfileAnchor *parent,
//                       struct ProfileAnchor *anchor) {
//        uint64_t elapsed_tsc= read_cpu_timer() - block->start_tsc;
//#if PROFILE_FAULTS
//        uint64_t elapsed_pagefault_count = read_os_pagefault_count() - block->start_pagefault_count;
//#endif
//#if PROFILE_L1_MISS
//        uint64_t elapsed_cache_miss_count = read_cache_miss() - block->start_cache_miss_count;
//#endif
//
//        parent->tsc_elapsed_exclusive -= elapsed_tsc;
//        anchor->tsc_elapsed_exclusive += elapsed_tsc;
//        anchor->tsc_elapsed_inclusive = block->old_tsc_elapsed_inclusive + elapsed_tsc;
//#if PROFILE_FAULTS
//        parent->pagefault_count_exclusive -= elapsed_pagefault_count;
//        anchor->pagefault_count_exclusive += elapsed_pagefault_count;
//        anchor->pagefault_count_inclusive = block->old_pagefault_count_inclusive + elapsed_pagefault_count;
//#endif
//#if PROFILE_L1_MISS
//        parent->cache_miss_count_exclusive -= elapsed_cache_miss_count;
//        anchor->cache_miss_count_exclusive += elapsed_cache_miss_count;
//        anchor->cache_miss_count_inclusive = block->old_cache_miss_count_inclusive + elapsed_cache_miss_count;
//#endif
//        ++anchor->hit_count;
//
//        /* NOTE(casey): This write happens every time solely because there is no
//           straightforward way in C++ to have the same ease-of-use. In a better programming
//           language, it would be simple to have the anchor points gathered and labeled at compile
//           time, and this repetative write would be eliminated. */
//        anchor->label = block->label;
//    }

//static void PrintTimeElapsed(FILE *stream, uint64_t TotalMissCount, uint64_t TotalPageFaultCount, uint64_t TotalTSCElapsed, uint64_t TimerFreq, profile_anchor *Anchor)
//{
//    double Percent = 100.0 * ((double)Anchor->TSCElapsedExclusive / (double)TotalTSCElapsed);
//    fprintf(stream, "%16s %10lu %16lu %5.2f", Anchor->Label, Anchor->HitCount, Anchor->TSCElapsedExclusive, Percent);
//    if(Anchor->TSCElapsedInclusive != Anchor->TSCElapsedExclusive)
//    {
//        double PercentWithChildren = 100.0 * ((double)Anchor->TSCElapsedInclusive / (double)TotalTSCElapsed);
//        fprintf(stream, " %10.2f", PercentWithChildren);
//    }
//    else
//    {
//        fprintf(stream, " %10.2f", 0.0f);
//    }
//
//    if(Anchor->ProcessedByteCount)
//    {
//        double Megabyte = 1024.0f*1024.0f;
//        double Gigabyte = Megabyte*1024.0f;
//
//        double Seconds = (double)Anchor->TSCElapsedInclusive / (double)TimerFreq;
//        double BytesPerSecond = (double)Anchor->ProcessedByteCount / Seconds;
//        double Megabytes = (double)Anchor->ProcessedByteCount / (double)Megabyte;
//        double GigabytesPerSecond = BytesPerSecond / Gigabyte;
//
//        fprintf(stream, " %8.3fmb at %5.2fgb/s", Megabytes, GigabytesPerSecond);
//    }
//
//
//    {
//        double Percent = 100.0 * ((double)Anchor->PageFaultCountExclusive / (double)TotalPageFaultCount);
//        fprintf(stream, " %6lu %5.2f", Anchor->PageFaultCountExclusive, Percent);
//        if(Anchor->PageFaultCountInclusive != Anchor->PageFaultCountExclusive)
//        {
//            double PercentWithChildren = 100.0 * ((double)Anchor->PageFaultCountInclusive / (double)TotalPageFaultCount);
//            fprintf(stream, " %10.2f", PercentWithChildren);
//        } else {
//            fprintf(stream, " %10.2f", 0.0f);
//        }
//    }
//
//    {
//        double Percent = 100.0 * ((double)Anchor->CacheMissCountExclusive / (double)TotalMissCount);
//        fprintf(stream, " %9lu %5.2f", Anchor->CacheMissCountExclusive, Percent);
//        if(Anchor->CacheMissCountInclusive != Anchor->CacheMissCountExclusive)
//        {
//            double PercentWithChildren = 100.0 * ((double)Anchor->CacheMissCountInclusive / (double)TotalMissCount);
//            fprintf(stream, " %10.2f", PercentWithChildren);
//        } else {
//            fprintf(stream, " %10.2f", 0.0f);
//        }
//    }
//
//    fprintf(stream, "\n");
//}

//static void PrintAnchorData(FILE *stream, uint64_t TotalMissCount, uint64_t TotalPageFaultCount, uint64_t TotalCPUElapsed, uint64_t TimerFreq) {
//    fprintf(stream, "%16s %10s %16s %5s %10s %6s %5s %10s %9s %5s %10s\n", "name", "samples", "TSC", "%", "% w/chld.", "faults", "%", "% w/chld.", "l1 misses", "%", "% w/chld.");
//    for (uint32_t AnchorIndex = 0; AnchorIndex < ARRAY_SIZE(GlobalProfilerAnchors); ++AnchorIndex)
//    {
//        profile_anchor *Anchor = GlobalProfilerAnchors + AnchorIndex;
//        if(Anchor->TSCElapsedInclusive)
//        {
//            PrintTimeElapsed(stream, TotalMissCount, TotalPageFaultCount, TotalCPUElapsed, TimerFreq, Anchor);
//        }
//    }
//}

static int fd_cache_miss;

uint64_t read_cache_miss(void) {
    long long count = 0;
    read(fd_cache_miss, &count, sizeof(long long));
    return count;
}

void start(void) {
    int fd;
    struct perf_event_attr pe;
    memset(&pe, 0, sizeof(struct perf_event_attr));
    pe.type = PERF_TYPE_HW_CACHE;
    pe.size = sizeof(struct perf_event_attr);
    pe.config = (CACHE_TYPE) |
                (PERF_COUNT_HW_CACHE_OP_READ << 8) |
                (PERF_COUNT_HW_CACHE_RESULT_MISS << 16);
    pe.disabled = 1;
    pe.exclude_kernel = 1;
    // Don't count hypervisor events.
    pe.exclude_hv = 1;

    fd = perf_event_open(&pe, 0, -1, -1, 0);
    assert(fd != -1);

    ioctl(fd, PERF_EVENT_IOC_RESET, 0);
    ioctl(fd, PERF_EVENT_IOC_ENABLE, 0);

    fd_cache_miss = fd;
}

void end(void) {
    ioctl(fd_cache_miss, PERF_EVENT_IOC_DISABLE, 0);
    close(fd_cache_miss);

    //uint64_t TimerFreq = estimate_cpu_timer_freq();
    //uint64_t TotalTSCElapsed = GlobalProfiler.EndTSC - GlobalProfiler.StartTSC;
    //uint64_t TotalFaults = GlobalProfiler.EndFaults - GlobalProfiler.StartFaults;
    //uint64_t TotalMissCount = GlobalProfiler.EndCacheMiss - GlobalProfiler.StartCacheMiss;

    //if(TimerFreq)
    //{
    //    fprintf(stream, "\nTotal time: %0.4fms (timer freq %lu)\n", 1000.0 * (double)TotalTSCElapsed / (double)TimerFreq, TimerFreq);
    //    fprintf(stream, "Total Page Fault count %lu\n", TotalFaults);
    //    fprintf(stream, "Total L1 cache miss count %lu\n", TotalMissCount);
    //}

    //PrintAnchorData(stream, TotalMissCount, TotalFaults, TotalTSCElapsed, TimerFreq);
}
