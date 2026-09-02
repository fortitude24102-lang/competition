#include "coremark.h"

#include <stdarg.h>

#include "timer.h"
#include "uart.h"

#define EE_TICKS_PER_SEC 100000000u

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;

ee_u32 default_num_contexts = 1;

static CORETIMETYPE start_time_value;
static CORETIMETYPE stop_time_value;

void start_time(void) {
  start_time_value = (CORETIMETYPE)timer_read();
}

void stop_time(void) {
  stop_time_value = (CORETIMETYPE)timer_read();
}

CORE_TICKS get_time(void) {
  return (CORE_TICKS)(stop_time_value - start_time_value);
}

secs_ret time_in_secs(CORE_TICKS ticks) {
  return ticks / EE_TICKS_PER_SEC;
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
  (void)argc;
  (void)argv;
  p->portable_id = 1;
}

void portable_fini(core_portable *p) {
  p->portable_id = 0;
}

static int print_unsigned(unsigned long value, unsigned base, int width, int zero_pad) {
  char digits[16];
  int count = 0;
  int written = 0;

  do {
    unsigned digit = (unsigned)(value % base);
    digits[count++] = (char)(digit < 10u ? '0' + digit : 'a' + digit - 10u);
    value /= base;
  } while (value != 0u);

  while (count < width) {
    uart_putc((uint8_t)(zero_pad ? '0' : ' '));
    ++written;
    --width;
  }
  while (count != 0) {
    uart_putc((uint8_t)digits[--count]);
    ++written;
  }
  return written;
}

int ee_printf(const char *format, ...) {
  va_list args;
  int written = 0;

  va_start(args, format);
  while (*format != '\0') {
    int width = 0;
    int zero_pad = 0;
    int long_value = 0;

    if (*format != '%') {
      uart_putc((uint8_t)*format++);
      ++written;
      continue;
    }
    ++format;
    if (*format == '0') {
      zero_pad = 1;
      ++format;
    }
    while (*format >= '0' && *format <= '9') {
      width = width * 10 + (*format++ - '0');
    }
    if (*format == 'l') {
      long_value = 1;
      ++format;
    }

    if (*format == 's') {
      const char *text = va_arg(args, const char *);
      while (*text != '\0') {
        uart_putc((uint8_t)*text++);
        ++written;
      }
    } else if (*format == 'd') {
      long value = long_value ? va_arg(args, long) : va_arg(args, int);
      if (value < 0) {
        uart_putc((uint8_t)'-');
        ++written;
        value = -value;
      }
      written += print_unsigned((unsigned long)value, 10u, width, zero_pad);
    } else if (*format == 'u') {
      unsigned long value = long_value ? va_arg(args, unsigned long)
                                        : va_arg(args, unsigned int);
      written += print_unsigned(value, 10u, width, zero_pad);
    } else if (*format == 'x') {
      unsigned long value = long_value ? va_arg(args, unsigned long)
                                        : va_arg(args, unsigned int);
      written += print_unsigned(value, 16u, width, zero_pad);
    } else if (*format == '%') {
      uart_putc((uint8_t)'%');
      ++written;
    }
    if (*format != '\0') {
      ++format;
    }
  }
  va_end(args);
  return written;
}
