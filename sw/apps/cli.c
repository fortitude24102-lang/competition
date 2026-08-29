#include <stdint.h>

#include "accel_driver.h"
#include "uart.h"

static int string_equal(const char *left, const char *right) {
  while (*left != '\0' && *left == *right) {
    ++left;
    ++right;
  }
  return *left == *right;
}

static int parse_u8(const char *text, uint8_t *value) {
  uint32_t parsed = 0;

  if (text == 0 || *text == '\0') {
    return -1;
  }
  while (*text != '\0') {
    if (*text < '0' || *text > '9') {
      return -1;
    }
    parsed = parsed * 10u + (uint32_t)(*text - '0');
    if (parsed > 255u) {
      return -1;
    }
    ++text;
  }
  *value = (uint8_t)parsed;
  return 0;
}

static int parse_switch(const char *text, uint32_t *value) {
  if (text == 0) {
    return -1;
  }
  if (string_equal(text, "on")) {
    *value = 1u;
    return 0;
  }
  if (string_equal(text, "off")) {
    *value = 0u;
    return 0;
  }
  return -1;
}

static void uart_put_u32(uint32_t value) {
  char digits[10];
  uint32_t count = 0;

  do {
    digits[count++] = (char)('0' + value % 10u);
    value /= 10u;
  } while (value != 0u);

  while (count != 0u) {
    uart_putc((uint8_t)digits[--count]);
  }
}

static void put_field(const char *name, uint32_t value) {
  uart_puts(name);
  uart_putc('=');
  uart_put_u32(value);
}

static char *split_argument(char *line) {
  while (*line != '\0' && *line != ' ') {
    ++line;
  }
  if (*line == '\0') {
    return 0;
  }
  *line++ = '\0';
  while (*line == ' ') {
    ++line;
  }
  return *line == '\0' ? 0 : line;
}

static int no_extra_space(const char *argument) {
  if (argument == 0) {
    return 0;
  }
  while (*argument != '\0') {
    if (*argument == ' ') {
      return -1;
    }
    ++argument;
  }
  return 0;
}

static void print_status(void) {
  put_field("enable", accel_read_enable());
  uart_putc(' ');
  put_field("mode", accel_read_mode());
  uart_putc(' ');
  put_field("threshold", accel_read_threshold());
  uart_putc(' ');
  put_field("bypass", accel_read_bypass());
  uart_putc('\n');
}

static void print_perf(void) {
  put_field("cycle", accel_read_cycle_count());
  uart_putc(' ');
  put_field("input", accel_read_input_count());
  uart_putc(' ');
  put_field("output", accel_read_output_count());
  uart_putc(' ');
  put_field("frame", accel_read_frame_count());
  uart_putc(' ');
  put_field("stall", accel_read_stall_count());
  uart_putc(' ');
  put_field("busy", accel_read_busy_cycles());
  uart_putc('\n');
}

static void execute_command(char *line) {
  char *argument = split_argument(line);
  uint8_t number;
  uint32_t switch_value;

  if (string_equal(line, "help") && argument == 0) {
    uart_puts("help status mode threshold bypass enable perf\n");
  } else if (string_equal(line, "status") && argument == 0) {
    print_status();
  } else if (string_equal(line, "mode") && no_extra_space(argument) == 0 &&
             parse_u8(argument, &number) == 0 && number <= ACCEL_MODE_THRESHOLD &&
             accel_set_mode(number) == 0) {
    uart_puts("OK\n");
  } else if (string_equal(line, "threshold") && no_extra_space(argument) == 0 &&
             parse_u8(argument, &number) == 0) {
    accel_set_threshold(number);
    uart_puts("OK\n");
  } else if (string_equal(line, "bypass") && no_extra_space(argument) == 0 &&
             parse_switch(argument, &switch_value) == 0) {
    accel_set_bypass(switch_value);
    uart_puts("OK\n");
  } else if (string_equal(line, "enable") && no_extra_space(argument) == 0 &&
             parse_switch(argument, &switch_value) == 0) {
    accel_set_enable(switch_value);
    uart_puts("OK\n");
  } else if (string_equal(line, "perf") && argument == 0) {
    print_perf();
  } else if (string_equal(line, "perf") && string_equal(argument, "clear")) {
    accel_perf_clear();
    uart_puts("OK\n");
  } else {
    uart_puts("ERR\n");
  }
}

int main(void) {
  char line[64];

  uart_puts("READY\n");
  for (;;) {
    int length = uart_readline(line, sizeof(line));
    if (length > 0) {
      execute_command(line);
    } else if (length < 0) {
      uart_puts("ERR\n");
    }
  }
}
