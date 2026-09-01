#include <stdint.h>

#include "gpio.h"
#include "timer.h"
#include "uart.h"

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
