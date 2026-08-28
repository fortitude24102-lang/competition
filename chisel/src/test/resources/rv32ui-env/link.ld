OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
  . = 0;
  .text : ALIGN(4)
  {
    *(.text.init)
    *(.text*)
  }
  .rodata : ALIGN(4) { *(.rodata*) }
  .data : ALIGN(16) { *(.data*) }
  .bss : ALIGN(16) { *(.bss*) *(COMMON) }

  /DISCARD/ :
  {
    *(.comment)
    *(.note*)
  }
}
