.section .text
.globl start
.globl _start

_start:
start:
  # Zero-init integer registers except x0 and stack pointer (x2 from CPU reset setup).
  li x1, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
  li x10, 0
  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  # Copy .data from load image to runtime address.
  la a0, _sidata
  la a1, _sdata
  la a2, _edata
1:
  bge a1, a2, 2f
  lw a3, 0(a0)
  sw a3, 0(a1)
  addi a0, a0, 4
  addi a1, a1, 4
  j 1b

  # Zero .bss.
2:
  la a0, _sbss
  la a1, _ebss
3:
  bge a0, a1, 4f
  sw zero, 0(a0)
  addi a0, a0, 4
  j 3b

4:
  call main
5:
  j 5b
