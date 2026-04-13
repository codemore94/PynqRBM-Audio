#define regnum_q0 0
#define regnum_q1 1
#define regnum_q2 2
#define regnum_q3 3

#define regnum_x0 0
#define regnum_x1 1
#define regnum_x2 2
#define regnum_x10 10

#define r_type_insn(_f7, _rs2, _rs1, _f3, _rd, _opc) \
.word (((_f7) << 25) | ((_rs2) << 20) | ((_rs1) << 15) | ((_f3) << 12) | ((_rd) << 7) | ((_opc) << 0))

#define picorv32_getq_insn(_rd, _qs) \
r_type_insn(0b0000000, 0, regnum_ ## _qs, 0b100, regnum_ ## _rd, 0b0001011)

#define picorv32_setq_insn(_qd, _rs) \
r_type_insn(0b0000001, 0, regnum_ ## _rs, 0b010, regnum_ ## _qd, 0b0001011)

#define picorv32_retirq_insn() \
r_type_insn(0b0000010, 0, 0, 0b000, 0, 0b0001011)

#define picorv32_maskirq_insn(_rd, _rs) \
r_type_insn(0b0000011, 0, regnum_ ## _rs, 0b110, regnum_ ## _rd, 0b0001011)

#define picorv32_waitirq_insn(_rd) \
r_type_insn(0b0000100, 0, 0, 0b100, regnum_ ## _rd, 0b0001011)

.section .text
.globl _start
.globl start
.globl rbm_irq_seen
.globl soc_irq_set_mask

_start:
start:
  // Keep the reset vector within the first 16 bytes. IRQ entry is at 0x10.
  j boot
  nop
  nop
  nop

.balign 16
irq_vec:
  picorv32_setq_insn(q2, x1)
  picorv32_setq_insn(q3, x2)
  lui x1, %hi(rbm_irq_seen)
  addi x1, x1, %lo(rbm_irq_seen)
  picorv32_getq_insn(x2, q1)
  sw x2, 0(x1)
  li x2, 2
  picorv32_maskirq_insn(x0, x2)
  picorv32_getq_insn(x2, q3)
  picorv32_getq_insn(x1, q2)
  picorv32_retirq_insn()

boot:
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

  la sp, _stack_top
  picorv32_maskirq_insn(x0, x0)

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

soc_irq_set_mask:
  picorv32_maskirq_insn(x10, x10)
  ret

.section .bss
.balign 4
rbm_irq_seen:
  .word 0
