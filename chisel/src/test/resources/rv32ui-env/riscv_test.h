#ifndef SMALLPROJECT_RISCV_TEST_H
#define SMALLPROJECT_RISCV_TEST_H

#define RVTEST_RV32U
#define RVTEST_RV64U

#define RVTEST_CODE_BEGIN                                               \
  .section .text.init;                                                  \
  .align 2;                                                             \
  .globl _start;                                                        \
_start:

#define RVTEST_CODE_END .align 2

#define TESTNUM gp

#define RVTEST_PASS                                                     \
  fence;                                                                \
  li t0, 1;                                                             \
  lui t1, 0x10;                                                        \
  sw t0, 0(t1);                                                        \
  ebreak

#define RVTEST_FAIL                                                     \
  fence;                                                                \
  lui t0, 0x10;                                                        \
  sw TESTNUM, 0(t0);                                                   \
  ebreak

#define RVTEST_DATA_BEGIN                                              \
  .align 4;                                                             \
  .globl begin_signature;                                              \
begin_signature:

#define RVTEST_DATA_END                                                \
  .align 4;                                                             \
  .globl end_signature;                                                \
end_signature:

#endif
