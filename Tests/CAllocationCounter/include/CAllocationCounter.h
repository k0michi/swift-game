#ifndef C_ALLOCATION_COUNTER_H
#define C_ALLOCATION_COUNTER_H

#include <stdbool.h>

// Counts the heap allocations and frees that the calling thread makes
// between begin and end, for tests of code that must not allocate. It wraps
// the malloc zones, so it is available only on Darwin.
bool allocation_counter_is_available(void);
void allocation_counter_begin(void);
// The allocations and frees since begin.
long allocation_counter_end(void);

#endif
