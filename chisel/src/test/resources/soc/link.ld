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

  /DISCARD/ :
  {
    *(.comment)
    *(.note*)
    *(.riscv.attributes)
  }
}
