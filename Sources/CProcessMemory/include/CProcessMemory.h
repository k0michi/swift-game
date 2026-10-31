#ifndef C_PROCESS_MEMORY_H
#define C_PROCESS_MEMORY_H

#include <stdint.h>

// The bytes of memory the process has in RAM now: its resident set, or its
// working set on Windows. In a browser, where a page's memory cannot be
// asked for, the size of the wasm memory, which only grows. 0 if it cannot
// be told.
uint64_t process_memory_current(void);

// The most the process has had in RAM, as process_memory_current counts.
uint64_t process_memory_peak(void);

#endif
