MEMORY { BRAM (rxw) : ORIGIN = 0x00000000, LENGTH = 128K }
SECTIONS {
.text : { *(.text*) *(.rodata*) } > BRAM
.data : { *(.data*) } > BRAM
.bss : { *(.bss*) } > BRAM
_heap_start = .; _heap_end = ORIGIN(BRAM)+LENGTH(BRAM);
}
