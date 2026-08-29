#include "uart.h"

#include "mmio.h"

#define UART_TXDATA 0x10000000u
#define UART_STATUS 0x10000004u
#define UART_RXDATA 0x10000008u

void uart_putc(uint8_t byte) {
  while ((mmio_read32(UART_STATUS) & 1u) == 0u) {
  }
  mmio_write32(UART_TXDATA, byte);
}

void uart_puts(const char *text) {
  while (*text != '\0') {
    uart_putc((uint8_t)*text);
    ++text;
  }
}

uint8_t uart_getc(void) {
  while ((mmio_read32(UART_STATUS) & 2u) == 0u) {
  }
  return (uint8_t)mmio_read32(UART_RXDATA);
}

int uart_readline(char *buffer, uint32_t capacity) {
  uint32_t length = 0;
  int overflow = 0;

  if (buffer == 0 || capacity < 2u) {
    return -1;
  }

  for (;;) {
    uint8_t byte = uart_getc();
    if (byte == '\r' || byte == '\n') {
      buffer[length] = '\0';
      return overflow ? -1 : (int)length;
    }
    if (byte == 8u || byte == 127u) {
      if (!overflow && length != 0u) {
        --length;
      }
    } else if (!overflow && length + 1u < capacity) {
      buffer[length++] = (char)byte;
    } else {
      overflow = 1;
    }
  }
}
