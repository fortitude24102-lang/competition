  .section .text.trap, "ax", @progbits
  .align 2
  .option norvc

  .globl machine_trap_entry
  .type machine_trap_entry, @function
machine_trap_entry:
  addi sp, sp, -16
  sw t0, 12(sp)
  sw t1, 8(sp)

  csrr t0, mcause
  la t1, trap_mcause
  sw t0, 0(t1)
  csrr t0, mepc
  la t1, trap_mepc
  sw t0, 0(t1)
  addi t0, t0, 4
  csrw mepc, t0

  lw t1, 8(sp)
  lw t0, 12(sp)
  addi sp, sp, 16
  mret
  .size machine_trap_entry, .-machine_trap_entry

  .globl machine_trap_test_call
  .globl machine_trap_test_ecall
  .type machine_trap_test_call, @function
machine_trap_test_call:
machine_trap_test_ecall:
  ecall
  ret
  .size machine_trap_test_call, .-machine_trap_test_call
