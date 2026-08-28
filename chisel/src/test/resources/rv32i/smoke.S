  .section .text.init
  .globl _start
  .option norvc

_start:
  lui   s0, 0x1
  sw    zero, 0(s0)
  sw    zero, 4(s0)

  # Upper-immediate, PC-relative, direct jump, and indirect jump.
  lui   t0, 0x12345
  lui   t1, 0x12345
  bne   t0, t1, fail

  auipc t2, 0
  addi  t2, t2, 12
  jal   t3, jal_target
  jal   zero, fail
jal_target:
  bne   t2, t3, fail

  auipc t4, 0
  addi  t4, t4, 17
  jalr  t5, t4, 0
  jal   zero, fail
jalr_target:
  addi  t4, t4, -5
  bne   t4, t5, fail

  # Immediate ALU and shift instructions.
  addi  t0, zero, -8
  slti  t1, t0, -7
  sltiu t2, t0, 1
  xori  t3, t0, -1
  ori   t4, zero, 0x55
  andi  t5, t4, 0x0f
  slli  t6, t1, 5
  srli  s1, t0, 28
  srai  s2, t0, 2
  addi  a0, zero, 1
  bne   t1, a0, fail
  bne   t2, zero, fail
  addi  a0, zero, 7
  bne   t3, a0, fail
  addi  a0, zero, 0x55
  bne   t4, a0, fail
  addi  a0, zero, 5
  bne   t5, a0, fail
  addi  a0, zero, 32
  bne   t6, a0, fail
  addi  a0, zero, 15
  bne   s1, a0, fail
  addi  a0, zero, -2
  bne   s2, a0, fail

  # Register ALU and shift instructions.
  addi  a0, zero, 7
  addi  a1, zero, 3
  add   a2, a0, a1
  sub   a3, a0, a1
  sll   a4, a0, a1
  slt   a5, a1, a0
  sltu  a6, a1, a0
  xor   a7, a0, a1
  lui   s4, 0x80000
  srl   s3, s4, a1
  sra   s5, s4, a1
  or    s6, a0, a1
  and   s7, a0, a1
  addi  t0, zero, 10
  bne   a2, t0, fail
  addi  t0, zero, 4
  bne   a3, t0, fail
  addi  t0, zero, 56
  bne   a4, t0, fail
  addi  t0, zero, 1
  bne   a5, t0, fail
  bne   a6, t0, fail
  addi  t0, zero, 4
  bne   a7, t0, fail
  lui   t0, 0x10000
  bne   s3, t0, fail
  lui   t0, 0xf0000
  bne   s5, t0, fail
  addi  t0, zero, 7
  bne   s6, t0, fail
  addi  t0, zero, 3
  bne   s7, t0, fail

  # Every conditional branch operation, using signed and unsigned orderings.
  addi  t0, zero, 1
  addi  t1, zero, 1
  beq   t0, t1, branch_beq
  jal   zero, fail
branch_beq:
  bne   t0, zero, branch_bne
  jal   zero, fail
branch_bne:
  addi  t0, zero, -1
  blt   t0, t1, branch_blt
  jal   zero, fail
branch_blt:
  bge   t1, t0, branch_bge
  jal   zero, fail
branch_bge:
  bltu  t1, t0, branch_bltu
  jal   zero, fail
branch_bltu:
  bgeu  t0, t1, branch_bgeu
  jal   zero, fail
branch_bgeu:

  # Byte, halfword, and word stores plus every RV32I load variant.
  addi  s1, s0, 0x100
  addi  t0, zero, -128
  sb    t0, 0(s1)
  lbu   t1, 0(s1)
  lb    t2, 0(s1)
  addi  t3, zero, 128
  bne   t1, t3, fail
  bne   t2, t0, fail

  lui   t3, 0x12
  addi  t3, t3, 0x345
  sh    t3, 2(s1)
  lhu   t4, 2(s1)
  lh    t5, 2(s1)
  lui   t6, 0x2
  addi  t6, t6, 0x345
  bne   t4, t6, fail
  bne   t5, t6, fail

  lui   t4, 0x12345
  addi  t4, t4, 0x678
  sw    t4, 4(s1)
  lw    t5, 4(s1)
  bne   t4, t5, fail

pass:
  lui   t0, 0x600dd
  addi  t0, t0, -0x502
  lui   t1, 0x12345
  addi  t1, t1, 0x678
  sw    t0, 0(s0)
  sw    t1, 4(s0)
  fence rw, rw
  ebreak

fail:
  lui   t0, 0x1
  addi  t0, t0, -0x453
  sw    t0, 0(s0)
  sw    zero, 4(s0)
  ebreak
