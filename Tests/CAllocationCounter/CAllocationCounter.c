#include "CAllocationCounter.h"

#if defined(__APPLE__)
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>

// libmalloc calls this, when set, on every allocation and free, as malloc
// stack logging does. It is not in a public header.
typedef void(malloc_logger_t)(
    uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t skipped_frames);
extern malloc_logger_t *malloc_logger;

static _Atomic(pthread_t) watched;
static atomic_long count;

static void counting_logger(
    uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result, uint32_t skipped_frames) {
    if (pthread_equal(pthread_self(), atomic_load(&watched))) {
        atomic_fetch_add(&count, 1);
    }
}

bool allocation_counter_is_available(void) {
    return true;
}

void allocation_counter_begin(void) {
    atomic_store(&watched, pthread_self());
    atomic_store(&count, 0);
    malloc_logger = counting_logger;
}

long allocation_counter_end(void) {
    malloc_logger = NULL;
    return atomic_load(&count);
}

#else

bool allocation_counter_is_available(void) {
    return false;
}

void allocation_counter_begin(void) {}

long allocation_counter_end(void) {
    return -1;
}

#endif
