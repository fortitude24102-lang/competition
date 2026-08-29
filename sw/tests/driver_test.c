#include <stdint.h>

#include "accel_driver.h"
#include "mmio.h"

#define UART_TXDATA 0x10000000u
#define UART_STATUS 0x10000004u

extern void clear_bss(void);
static volatile uint32_t bss_probe;

static void uart_putc(uint8_t byte) {
  while ((mmio_read32(UART_STATUS) & 1u) == 0u) {
  }
  mmio_write32(UART_TXDATA, byte);
}

int main(void) {
  int ok = 1;

  ok &= bss_probe == 0u;
  bss_probe = 0xa5a55a5au;
  clear_bss();
  ok &= bss_probe == 0u;

  accel_set_enable(1);
  ok &= accel_set_mode(ACCEL_MODE_THRESHOLD) == 0;
  accel_set_threshold(128);
  accel_set_bypass(0);
  ok &= accel_set_mode(3) == -1;

  ok &= accel_read_enable() == 1;
  ok &= accel_read_mode() == ACCEL_MODE_THRESHOLD;
  ok &= accel_read_threshold() == 128;
  ok &= accel_read_bypass() == 0;

#ifdef FORCE_FAILURE
  ok = 0;
#endif

  uart_putc(ok ? 'P' : 'F');
  return ok ? 0 : 1;
}
