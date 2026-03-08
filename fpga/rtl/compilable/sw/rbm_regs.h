#ifndef RBM_REGS_H
#define RBM_REGS_H

#include <stdint.h>

// AXI-Lite register offsets
#define RBM_REG_CONTROL        0x00u
#define RBM_REG_STATUS         0x04u
#define RBM_REG_I_DIM          0x08u
#define RBM_REG_H_DIM          0x0Cu
#define RBM_REG_K_DIM          0x10u
#define RBM_REG_FRAME_LEN      0x14u
#define RBM_REG_SCALE_SHIFT    0x18u
#define RBM_REG_RNG_SEED       0x1Cu
#define RBM_REG_INT_EN         0x20u
#define RBM_REG_INT_STATUS     0x24u
#define RBM_REG_TILE_IH        0x28u
#define RBM_REG_BATCH_SIZE     0x2Cu
#define RBM_REG_EPOCHS         0x30u
#define RBM_REG_LR_MOM         0x34u
#define RBM_REG_WEIGHT_DECAY   0x38u
#define RBM_REG_STATS          0x3Cu
#define RBM_REG_W_BASE_LO      0x40u
#define RBM_REG_W_BASE_HI      0x44u
#define RBM_REG_B_VIS_BASE     0x48u
#define RBM_REG_B_HID_BASE     0x4Cu
#define RBM_REG_DATA_BASE_LO   0x50u
#define RBM_REG_DATA_BASE_HI   0x54u
#define RBM_REG_HW_VERSION     0x58u
#define RBM_REG_PERF_CYCLES    0x5Cu
#define RBM_REG_PERF_UPDATES   0x60u
#define RBM_REG_PERF_STALLS    0x64u
#define RBM_REG_ACCUM_CTRL     0x68u
#define RBM_REG_MEM_ADDR       0x6Cu
#define RBM_REG_MEM_WDATA      0x70u
#define RBM_REG_MEM_RDATA      0x74u
#define RBM_REG_MEM_CTRL       0x78u

// CONTROL register bits
#define RBM_CTRL_START         (1u << 0)
#define RBM_CTRL_SOFT_RST      (1u << 1)
#define RBM_CTRL_MODE_TRAIN    (1u << 2)
#define RBM_CTRL_DETERM        (1u << 3)
#define RBM_CTRL_DMA_EN        (1u << 4)

// STATUS register bits
#define RBM_STATUS_BUSY        (1u << 0)
#define RBM_STATUS_DONE        (1u << 1)
#define RBM_STATUS_ERR         (1u << 2)
#define RBM_STATUS_BATCH_DONE  (1u << 3)
#define RBM_STATUS_EPOCH_DONE  (1u << 4)

static inline void rbm_wr(uintptr_t base, uint32_t off, uint32_t value) {
  *(volatile uint32_t *)(base + off) = value;
}

static inline uint32_t rbm_rd(uintptr_t base, uint32_t off) {
  return *(volatile uint32_t *)(base + off);
}

static inline void rbm_mem_write(uintptr_t base, uint32_t sel, uint32_t addr, uint32_t data) {
  rbm_wr(base, RBM_REG_MEM_CTRL, sel & 0x7u);
  rbm_wr(base, RBM_REG_MEM_ADDR, addr);
  rbm_wr(base, RBM_REG_MEM_WDATA, data);
}

static inline uint32_t rbm_mem_read(uintptr_t base, uint32_t sel, uint32_t addr) {
  rbm_wr(base, RBM_REG_MEM_CTRL, sel & 0x7u);
  rbm_wr(base, RBM_REG_MEM_ADDR, addr);
  return rbm_rd(base, RBM_REG_MEM_RDATA);
}

#endif
