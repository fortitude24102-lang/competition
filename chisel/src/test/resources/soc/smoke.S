  .section .text.init
  .globl _start
  .option norvc

_start:
  # Accelerator base: 0x3000_0000.
  lui   t0, 0x30000
  addi  t1, zero, 1
  sw    t1, 0(t0)
  addi  t1, zero, 2
  sw    t1, 8(t0)
  addi  t1, zero, 128
  sw    t1, 12(t0)
  sw    zero, 16(t0)

  lw    t2, 8(t0)
  addi  t3, zero, 2
  bne   t2, t3, fail
  lw    t2, 12(t0)
  addi  t3, zero, 128
  bne   t2, t3, fail

pass:
  lui   t4, 0x10000
  addi  t5, zero, 80
  sw    t5, 0(t4)
  ebreak

fail:
  lui   t4, 0x10000
  addi  t5, zero, 70
  sw    t5, 0(t4)
  ebreak
