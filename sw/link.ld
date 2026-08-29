OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  ram (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
  .text : ALIGN(4)
  {
    *(.text.init)
    *(.text*)
  } > ram

  .rodata : ALIGN(4) { *(.rodata*) } > ram
  .data : ALIGN(4) { *(.data*) } > ram
  .bss : ALIGN(4)
  {
    *(.bss*)
    *(COMMON)
  } > ram

  _stack_top = ORIGIN(ram) + LENGTH(ram);

  /DISCARD/ :
  {
    *(.comment)
    *(.note*)
    *(.riscv.attributes)
  }
}
