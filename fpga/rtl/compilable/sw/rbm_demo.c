#include <stdint.h>

#include "rbm_regs.h"

// Replace with your SoC memory map.
#define RBM_BASE_ADDR 0x40000000u

static void rbm_config_default(uintptr_t base) {
  rbm_wr(base, RBM_REG_I_DIM, 64);
  rbm_wr(base, RBM_REG_H_DIM, 64);
  rbm_wr(base, RBM_REG_K_DIM, 1);
  rbm_wr(base, RBM_REG_FRAME_LEN, 1);
  rbm_wr(base, RBM_REG_SCALE_SHIFT, 0);
  rbm_wr(base, RBM_REG_RNG_SEED, 0xACE1u);
  rbm_wr(base, RBM_REG_BATCH_SIZE, 1);
  rbm_wr(base, RBM_REG_EPOCHS, 1);
  rbm_wr(base, RBM_REG_LR_MOM, 0x00000100u);  // lr=0x0100, mom=0
  rbm_wr(base, RBM_REG_WEIGHT_DECAY, 0);
}

static void rbm_load_tiny_case(uintptr_t base) {
  uint32_t i, h;
  for (i = 0; i < 4; ++i) {
    rbm_mem_write(base, 0u, i, (i & 1u) ? 0x80u : 0x00u);  // v0
    rbm_mem_write(base, 2u, i, 0u);                         // b_vis
    for (h = 0; h < 4; ++h) {
      rbm_mem_write(base, 1u, (h << 16) | i, 0x0100u);      // w[i][h]
    }
  }
  for (h = 0; h < 4; ++h) {
    rbm_mem_write(base, 3u, h, 0u);                         // b_hid
  }
}

static int rbm_run_once_poll(uintptr_t base, uint32_t timeout_cycles) {
  uint32_t status;
  rbm_wr(base, RBM_REG_CONTROL, RBM_CTRL_DETERM | RBM_CTRL_START);
  rbm_wr(base, RBM_REG_CONTROL, RBM_CTRL_DETERM);

  while (timeout_cycles--) {
    status = rbm_rd(base, RBM_REG_STATUS);
    if (status & RBM_STATUS_DONE) return 0;
    if (status & RBM_STATUS_ERR) return -2;
  }
  return -1;
}

int main(void) {
  uintptr_t base = (uintptr_t)RBM_BASE_ADDR;
  uint32_t version = rbm_rd(base, RBM_REG_HW_VERSION);
  if (version != 0x00010000u) return 10;

  rbm_config_default(base);
  rbm_load_tiny_case(base);
  if (rbm_run_once_poll(base, 5000000u) != 0) return 20;

  // Probe outputs/counters for firmware bring-up sanity.
  (void)rbm_mem_read(base, 1u, 0u);
  (void)rbm_rd(base, RBM_REG_PERF_CYCLES);
  (void)rbm_rd(base, RBM_REG_PERF_UPDATES);
  (void)rbm_rd(base, RBM_REG_PERF_STALLS);

  return 0;
}
