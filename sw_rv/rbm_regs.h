#ifndef RBM_REGS_H
#define RBM_REGS_H

#include <stdint.h>

// Base address for RBM AXI-Lite control block
#ifndef RBM_BASE_ADDR
#define RBM_BASE_ADDR 0x40002000u
#endif

// Register offsets (match fpga/rtl/compilable/rbm_ctrl_axi_lite.sv)
#define RBM_REG_CONTROL      0x00u
#define RBM_REG_STATUS       0x04u
#define RBM_REG_I_DIM        0x08u
#define RBM_REG_H_DIM        0x0Cu
#define RBM_REG_K_DIM        0x10u
#define RBM_REG_FRAME_LEN    0x14u
#define RBM_REG_SCALE_SHIFT  0x18u
#define RBM_REG_RNG_SEED     0x1Cu
#define RBM_REG_INT_EN       0x20u
#define RBM_REG_INT_STATUS   0x24u
#define RBM_REG_TILE_IH      0x28u
#define RBM_REG_BATCH_SIZE   0x2Cu
#define RBM_REG_EPOCHS       0x30u
#define RBM_REG_LR_MOM       0x34u
#define RBM_REG_WEIGHT_DECAY 0x38u
#define RBM_REG_STATS        0x3Cu
#define RBM_REG_W_BASE_LO    0x40u
#define RBM_REG_W_BASE_HI    0x44u
#define RBM_REG_B_VIS_BASE   0x48u
#define RBM_REG_B_HID_BASE   0x4Cu
#define RBM_REG_DATA_BASE_LO 0x50u
#define RBM_REG_DATA_BASE_HI 0x54u
#define RBM_REG_ACCUM_CTRL   0x68u
#define RBM_REG_MEM_ADDR     0x6Cu
#define RBM_REG_MEM_WDATA    0x70u
#define RBM_REG_MEM_RDATA    0x74u
#define RBM_REG_MEM_CTRL     0x78u

// CONTROL bits
#define RBM_CTRL_START     (1u << 0)
#define RBM_CTRL_SOFT_RST  (1u << 1)
#define RBM_CTRL_MODE_TRAIN (1u << 2)
#define RBM_CTRL_DETERM    (1u << 3)
#define RBM_CTRL_DMA_EN    (1u << 4)

// STATUS bits
#define RBM_STATUS_BUSY        (1u << 0)
#define RBM_STATUS_DONE        (1u << 1)
#define RBM_STATUS_ERR         (1u << 2)
#define RBM_STATUS_BATCH_DONE  (1u << 3)
#define RBM_STATUS_EPOCH_DONE  (1u << 4)

// MEM_CTRL selections
#define RBM_MEM_SEL_V0      0u
#define RBM_MEM_SEL_W       1u
#define RBM_MEM_SEL_B_VIS   2u
#define RBM_MEM_SEL_B_HID   3u
#define RBM_MEM_SEL_H0_PROB 4u
#define RBM_MEM_SEL_H1_PROB 5u

#define RBM_REG(off) (*(volatile uint32_t *)((RBM_BASE_ADDR) + (off)))

// Register block view (includes padding for gaps)
typedef struct {
  volatile uint32_t CONTROL;      // 0x00
  volatile uint32_t STATUS;       // 0x04
  volatile uint32_t I_DIM;        // 0x08
  volatile uint32_t H_DIM;        // 0x0C
  volatile uint32_t K_DIM;        // 0x10
  volatile uint32_t FRAME_LEN;    // 0x14
  volatile uint32_t SCALE_SHIFT;  // 0x18
  volatile uint32_t RNG_SEED;     // 0x1C
  volatile uint32_t INT_EN;       // 0x20
  volatile uint32_t INT_STATUS;   // 0x24
  volatile uint32_t TILE_IH;      // 0x28
  volatile uint32_t BATCH_SIZE;   // 0x2C
  volatile uint32_t EPOCHS;       // 0x30
  volatile uint32_t LR_MOM;       // 0x34
  volatile uint32_t WEIGHT_DECAY; // 0x38
  volatile uint32_t STATS;        // 0x3C
  volatile uint32_t W_BASE_LO;    // 0x40
  volatile uint32_t W_BASE_HI;    // 0x44
  volatile uint32_t B_VIS_BASE;   // 0x48
  volatile uint32_t B_HID_BASE;   // 0x4C
  volatile uint32_t DATA_BASE_LO; // 0x50
  volatile uint32_t DATA_BASE_HI; // 0x54
  volatile uint32_t _reserved0[4]; // 0x58..0x64
  volatile uint32_t ACCUM_CTRL;   // 0x68
  volatile uint32_t MEM_ADDR;     // 0x6C
  volatile uint32_t MEM_WDATA;    // 0x70
  volatile uint32_t MEM_RDATA;    // 0x74
  volatile uint32_t MEM_CTRL;     // 0x78
} RbmRegs;

#define RBM ((RbmRegs *)RBM_BASE_ADDR)

// Backward-compat aliases used by existing code
#define ACCEL RBM
#define ACCEL_CTRL_START RBM_CTRL_START
#define REG(off) RBM_REG(off)

#endif // RBM_REGS_H
