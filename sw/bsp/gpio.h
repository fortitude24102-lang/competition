#ifndef SMALLPROJECT_GPIO_H
#define SMALLPROJECT_GPIO_H

#include <stdint.h>

#include "mmio.h"

#define GPIO_OUTPUT 0x10001000u
#define GPIO_INPUT  0x10001004u

static inline void gpio_write(uint8_t value) {
  mmio_write32(GPIO_OUTPUT, value);
}

static inline uint8_t gpio_read(void) {
  return (uint8_t)mmio_read32(GPIO_INPUT);
}

#endif
