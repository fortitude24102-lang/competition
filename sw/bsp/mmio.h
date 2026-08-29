#ifndef SMALLPROJECT_MMIO_H
#define SMALLPROJECT_MMIO_H

#include <stdint.h>

static inline void mmio_write32(uintptr_t address, uint32_t value) {
  *(volatile uint32_t *)address = value;
}

static inline uint32_t mmio_read32(uintptr_t address) {
  return *(volatile const uint32_t *)address;
}

#endif
