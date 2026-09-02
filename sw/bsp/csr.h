#ifndef SMALLPROJECT_CSR_H
#define SMALLPROJECT_CSR_H

#include <stdint.h>

static inline void csr_write_mtvec(uint32_t value) {
  __asm__ volatile("csrw mtvec, %0" : : "r"(value) : "memory");
}

#endif
