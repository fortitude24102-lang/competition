#include "accel_driver.h"
#include "mmio.h"

static uintptr_t accel_register(uint32_t offset) {
  return (uintptr_t)(ACCEL_BASE + offset);
}

void accel_set_enable(uint32_t enable) {
  mmio_write32(accel_register(ACCEL_CTRL_OFFSET), enable != 0u);
}

int accel_set_mode(uint32_t mode) {
  if (mode > ACCEL_MODE_THRESHOLD) {
    return -1;
  }
  mmio_write32(accel_register(ACCEL_MODE_OFFSET), mode);
  return 0;
}

void accel_set_threshold(uint8_t threshold) {
  mmio_write32(accel_register(ACCEL_THRESHOLD_OFFSET), threshold);
}

void accel_set_bypass(uint32_t bypass) {
  mmio_write32(accel_register(ACCEL_BYPASS_OFFSET), bypass != 0u);
}

uint32_t accel_get_status(void) {
  return mmio_read32(accel_register(ACCEL_STATUS_OFFSET));
}

uint32_t accel_read_enable(void) {
  return mmio_read32(accel_register(ACCEL_CTRL_OFFSET)) & 1u;
}

uint32_t accel_read_mode(void) {
  return mmio_read32(accel_register(ACCEL_MODE_OFFSET)) & 3u;
}

uint32_t accel_read_threshold(void) {
  return mmio_read32(accel_register(ACCEL_THRESHOLD_OFFSET)) & 0xffu;
}

uint32_t accel_read_bypass(void) {
  return mmio_read32(accel_register(ACCEL_BYPASS_OFFSET)) & 1u;
}
