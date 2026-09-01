#include <stdint.h>

#include "gpio.h"
#include "mmio.h"
#include "timer.h"

#define UART_TXDATA 0x10000000u
#define UART_STATUS 0x10000004u

static void uart_putc(uint8_t byte) {
  while ((mmio_read32(UART_STATUS) & 1u) == 0u) {
  }
  mmio_write32(UART_TXDATA, byte);
}

int main(void) {
  int ok = gpio_read() == 0x3cu;
  uint64_t start;
  uint64_t end;

  gpio_write(0xa5u);
  start = timer_read();
  for (uint32_t index = 0; index < 16u; ++index) {
    __asm__ volatile("nop");
  }
  end = timer_read();
  ok &= end > start;

  uart_putc(ok ? 'P' : 'F');
  return ok ? 0 : 1;
}
