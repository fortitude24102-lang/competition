#include <stdint.h>

#include "csr.h"
#include "uart.h"

volatile uint32_t trap_mcause;
volatile uint32_t trap_mepc;

extern void machine_trap_entry(void);
extern void machine_trap_test_call(void);
extern const uint8_t machine_trap_test_ecall;

int main(void) {
  csr_write_mtvec((uint32_t)(uintptr_t)machine_trap_entry);
  machine_trap_test_call();

  int ok = trap_mcause == 11u;
  ok &= trap_mepc == (uint32_t)(uintptr_t)&machine_trap_test_ecall;
  uart_putc(ok ? 'P' : 'F');
  return ok ? 0 : 1;
}
