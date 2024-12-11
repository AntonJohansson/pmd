#pragma once

#include <stdint.h>

// inclusive == Does include child anchors
// exclusive == Does not include child anchors

void start(void);
void end(void);
uint64_t read_os_pagefault_count(void);
uint64_t read_cpu_timer(void);
uint64_t read_cache_miss(void);
uint64_t estimate_cpu_timer_freq(void);
