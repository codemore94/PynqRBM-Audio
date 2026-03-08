ENTRY(start)

MEMORY
{
  RAM (xrw) : ORIGIN = 0x00000000, LENGTH = 0x00004000
}

SECTIONS
{
  .text : {
    . = ALIGN(4);
    *(.text)
    *(.text*)
    *(.rodata)
    *(.rodata*)
    . = ALIGN(4);
    _etext = .;
    _sidata = _etext;
  } > RAM

  .data : AT(_sidata) {
    . = ALIGN(4);
    _sdata = .;
    *(.data)
    *(.data*)
    *(.sdata)
    *(.sdata*)
    . = ALIGN(4);
    _edata = .;
  } > RAM

  .bss : {
    . = ALIGN(4);
    _sbss = .;
    *(.bss)
    *(.bss*)
    *(.sbss)
    *(.sbss*)
    *(COMMON)
    . = ALIGN(4);
    _ebss = .;
  } > RAM

  .heap : {
    . = ALIGN(4);
    _heap_start = .;
  } > RAM
}
