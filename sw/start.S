  .section .text.init
  .globl _start
  .option norvc

_start:
  la sp, _stack_top
  call main
  ebreak

1:
  j 1b
