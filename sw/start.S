  .section .text.init
  .globl _start
  .option norvc

_start:
  la sp, _stack_top
  call clear_bss
  call main
  ebreak

1:
  j 1b

  .globl clear_bss
clear_bss:
  la t0, __bss_start
  la t1, __bss_end
2:
  bgeu t0, t1, 3f
  sw zero, 0(t0)
  addi t0, t0, 4
  j 2b
3:
  ret
