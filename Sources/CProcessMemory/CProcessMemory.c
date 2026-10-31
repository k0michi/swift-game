#include "CProcessMemory.h"

#if defined(__EMSCRIPTEN__)
#include <emscripten/heap.h>

uint64_t process_memory_current(void) {
    return emscripten_get_heap_size();
}

uint64_t process_memory_peak(void) {
    // The wasm memory never shrinks.
    return emscripten_get_heap_size();
}

#elif defined(__APPLE__)
#include <mach/mach.h>

static int basic_info(mach_task_basic_info_data_t *info) {
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    return task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)info, &count) == KERN_SUCCESS;
}

uint64_t process_memory_current(void) {
    mach_task_basic_info_data_t info;
    return basic_info(&info) ? info.resident_size : 0;
}

uint64_t process_memory_peak(void) {
    mach_task_basic_info_data_t info;
    return basic_info(&info) ? info.resident_size_max : 0;
}

#elif defined(_WIN32)
// K32GetProcessMemoryInfo in kernel32, rather than psapi.lib.
#define PSAPI_VERSION 2
#include <windows.h>
#include <psapi.h>

static int counters(PROCESS_MEMORY_COUNTERS *counters) {
    return GetProcessMemoryInfo(GetCurrentProcess(), counters, sizeof *counters) != 0;
}

uint64_t process_memory_current(void) {
    PROCESS_MEMORY_COUNTERS info;
    return counters(&info) ? info.WorkingSetSize : 0;
}

uint64_t process_memory_peak(void) {
    PROCESS_MEMORY_COUNTERS info;
    return counters(&info) ? info.PeakWorkingSetSize : 0;
}

#elif defined(__linux__)
#include <stdio.h>
#include <sys/resource.h>
#include <unistd.h>

uint64_t process_memory_current(void) {
    // The second field of statm is the resident set, in pages.
    FILE *file = fopen("/proc/self/statm", "r");
    if (!file) return 0;
    unsigned long long size = 0, resident = 0;
    int read = fscanf(file, "%llu %llu", &size, &resident);
    fclose(file);
    long page = sysconf(_SC_PAGESIZE);
    return read == 2 && page > 0 ? resident * (uint64_t)page : 0;
}

uint64_t process_memory_peak(void) {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) != 0) return 0;
    // Linux counts ru_maxrss in kilobytes, and updates it later than the
    // resident set, so it can fall behind what statm says now.
    uint64_t peak = (uint64_t)usage.ru_maxrss * 1024;
    uint64_t current = process_memory_current();
    return current > peak ? current : peak;
}

#else
uint64_t process_memory_current(void) {
    return 0;
}

uint64_t process_memory_peak(void) {
    return 0;
}
#endif
