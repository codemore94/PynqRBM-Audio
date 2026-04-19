#ifndef RBM_REGS_H
#define RBM_REGS_H

#include <stdint.h>

#define RBM_HW_VERSION         0x00010000u
#define TINY_ATTN_HW_VERSION   0x00011000u

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

// MEM_CTRL select values
#define RBM_MEMSEL_V0          0u
#define RBM_MEMSEL_W           1u
#define RBM_MEMSEL_B_VIS       2u
#define RBM_MEMSEL_B_HID       3u
#define RBM_MEMSEL_H0_PROB     4u
#define RBM_MEMSEL_H1_PROB     5u

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

// STATS register packing
#define RBM_STATS_BATCH_SHIFT  0u
#define RBM_STATS_EPOCH_SHIFT  16u
#define RBM_STATS_FIELD_MASK   0xFFFFu

static inline uint32_t rbm_stats_batch(uint32_t stats) {
  return (stats >> RBM_STATS_BATCH_SHIFT) & RBM_STATS_FIELD_MASK;
}

static inline uint32_t rbm_stats_epoch(uint32_t stats) {
  return (stats >> RBM_STATS_EPOCH_SHIFT) & RBM_STATS_FIELD_MASK;
}

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

// Tiny attention AXI-Lite register offsets
#define TINY_REG_CONTROL       0x00u
#define TINY_REG_STATUS        0x04u
#define TINY_REG_SEQ_LEN       0x08u
#define TINY_REG_D_MODEL       0x0Cu
#define TINY_REG_D_HEAD        0x10u
#define TINY_REG_SCORE_SHIFT   0x14u
#define TINY_REG_NORM_BIAS     0x18u
#define TINY_REG_INT_EN        0x1Cu
#define TINY_REG_INT_STATUS    0x20u
#define TINY_REG_TOKEN_BASE_LO 0x24u
#define TINY_REG_TOKEN_BASE_HI 0x28u
#define TINY_REG_WQ_BASE       0x2Cu
#define TINY_REG_WK_BASE       0x30u
#define TINY_REG_WV_BASE       0x34u
#define TINY_REG_WO_BASE       0x38u
#define TINY_REG_OUT_BASE      0x3Cu
#define TINY_REG_HW_VERSION    0x40u
#define TINY_REG_PERF_CYCLES   0x44u
#define TINY_REG_PERF_MACS     0x48u
#define TINY_REG_PERF_STALLS   0x4Cu
#define TINY_REG_MEM_ADDR      0x54u
#define TINY_REG_MEM_WDATA     0x58u
#define TINY_REG_MEM_RDATA     0x5Cu
#define TINY_REG_MEM_CTRL      0x60u

// Tiny attention MEM_CTRL select values
#define TINY_MEMSEL_TOKEN      0u
#define TINY_MEMSEL_WQ         1u
#define TINY_MEMSEL_WK         2u
#define TINY_MEMSEL_WV         3u
#define TINY_MEMSEL_WO         4u
#define TINY_MEMSEL_OUT        5u
#define TINY_MEMSEL_ATTN       6u
#define TINY_MEMSEL_ADAPT      7u

// For TINY_MEMSEL_ADAPT, MEM_ADDR[31:16] selects:
// 0..SEQ_LEN-1   -> target row
// 16'hfffe       -> adapter gain row, index by MEM_ADDR[15:0]
// 16'hffff       -> adapter bias row, index by MEM_ADDR[15:0]

// Tiny attention CONTROL bits
#define TINY_CTRL_START        (1u << 0)
#define TINY_CTRL_SOFT_RST     (1u << 1)
#define TINY_CTRL_MODE_TRAIN   (1u << 2)
#define TINY_CTRL_USE_OUT_PROJ (1u << 3)
#define TINY_CTRL_CAUSAL       (1u << 4)
#define TINY_CTRL_MODE_FULL_BP (1u << 5)

// Tiny attention STATUS bits
#define TINY_STATUS_BUSY       (1u << 0)
#define TINY_STATUS_DONE       (1u << 1)
#define TINY_STATUS_ERR        (1u << 2)

static inline void tiny_wr(uintptr_t base, uint32_t off, uint32_t value) {
  *(volatile uint32_t *)(base + off) = value;
}

static inline uint32_t tiny_rd(uintptr_t base, uint32_t off) {
  return *(volatile uint32_t *)(base + off);
}

static inline void tiny_mem_write(uintptr_t base, uint32_t sel, uint32_t addr, uint32_t data) {
  tiny_wr(base, TINY_REG_MEM_CTRL, sel & 0x7u);
  tiny_wr(base, TINY_REG_MEM_ADDR, addr);
  tiny_wr(base, TINY_REG_MEM_WDATA, data);
}

static inline uint32_t tiny_mem_read(uintptr_t base, uint32_t sel, uint32_t addr) {
  tiny_wr(base, TINY_REG_MEM_CTRL, sel & 0x7u);
  tiny_wr(base, TINY_REG_MEM_ADDR, addr);
  return tiny_rd(base, TINY_REG_MEM_RDATA);
}

#endif
