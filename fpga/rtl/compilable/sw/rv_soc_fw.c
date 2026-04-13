#include <stdint.h>

#include "rbm_regs.h"

#define UART_DIV   (*(volatile uint32_t *)0x10000000u)
#define UART_DATA  (*(volatile uint32_t *)0x10000004u)
#define TIMER_CTRL (*(volatile uint32_t *)0x10001010u)
#define RBM_BASE   0x40000000u

extern volatile uint32_t rbm_irq_seen;
extern uint32_t soc_irq_set_mask(uint32_t new_mask);

static void uart_putc(char c) {
  while ((UART_DATA & 0x80000000u) == 0u) {
  }
  UART_DATA = (uint32_t)(uint8_t)c;
}

static void uart_puts(const char *s) {
  while (*s) uart_putc(*s++);
}

static void uart_put_hex4(uint32_t v) {
  v &= 0xFu;
  uart_putc(v < 10 ? ('0' + v) : ('A' + (v - 10)));
}

static void uart_put_hex32(uint32_t v) {
  int i;
  for (i = 7; i >= 0; --i) uart_put_hex4(v >> (i * 4));
}

static void uart_put_dec(uint32_t v) {
  char buf[10];
  int i = 0;
  if (v == 0) {
    uart_putc('0');
    return;
  }
  while (v != 0 && i < (int)sizeof(buf)) {
    buf[i++] = (char)('0' + (v % 10u));
    v /= 10u;
  }
  while (i > 0) uart_putc(buf[--i]);
}

static void uart_put_label_hex(const char *label, uint32_t v) {
  uart_puts(label);
  uart_puts("0x");
  uart_put_hex32(v);
  uart_putc('\n');
}

static void uart_put_label_dec(const char *label, uint32_t v) {
  uart_puts(label);
  uart_put_dec(v);
  uart_putc('\n');
}

static uint32_t mem_addr_2d(uint32_t i_idx, uint32_t h_idx) {
  return (h_idx << 16) | i_idx;
}

static void rbm_load_case(uint32_t i_dim, uint32_t h_dim, uint32_t weight) {
  uint32_t i, h;

  rbm_wr(RBM_BASE, RBM_REG_CONTROL, RBM_CTRL_SOFT_RST);
  rbm_wr(RBM_BASE, RBM_REG_CONTROL, 0);
  rbm_wr(RBM_BASE, RBM_REG_I_DIM, i_dim);
  rbm_wr(RBM_BASE, RBM_REG_H_DIM, h_dim);
  rbm_wr(RBM_BASE, RBM_REG_K_DIM, 1);
  rbm_wr(RBM_BASE, RBM_REG_FRAME_LEN, 1);
  rbm_wr(RBM_BASE, RBM_REG_SCALE_SHIFT, 0);
  rbm_wr(RBM_BASE, RBM_REG_RNG_SEED, 0xACE1u);
  rbm_wr(RBM_BASE, RBM_REG_INT_EN, 1u);
  rbm_wr(RBM_BASE, RBM_REG_BATCH_SIZE, 1);
  rbm_wr(RBM_BASE, RBM_REG_EPOCHS, 1);
  rbm_wr(RBM_BASE, RBM_REG_LR_MOM, 0x00000100u);
  rbm_wr(RBM_BASE, RBM_REG_WEIGHT_DECAY, 0);

  for (i = 0; i < i_dim; ++i) {
    rbm_mem_write(RBM_BASE, RBM_MEMSEL_V0, i, (i & 1u) ? 0x80u : 0x00u);
    rbm_mem_write(RBM_BASE, RBM_MEMSEL_B_VIS, i, 0u);
    for (h = 0; h < h_dim; ++h) {
      rbm_mem_write(RBM_BASE, RBM_MEMSEL_W, mem_addr_2d(i, h), weight);
    }
  }

  for (h = 0; h < h_dim; ++h) {
    rbm_mem_write(RBM_BASE, RBM_MEMSEL_B_HID, h, 0u);
  }
}

static int rbm_self_check_load(uint32_t i_dim, uint32_t h_dim, uint32_t weight) {
  uint32_t got_v0 = rbm_mem_read(RBM_BASE, RBM_MEMSEL_V0, 1u);
  uint32_t got_w00 = rbm_mem_read(RBM_BASE, RBM_MEMSEL_W, mem_addr_2d(0u, 0u));
  uint32_t got_bh = rbm_mem_read(RBM_BASE, RBM_MEMSEL_B_HID, h_dim - 1u);

  if ((got_v0 & 0xFFu) != 0x80u) return 10;
  if ((got_w00 & 0xFFFFu) != (weight & 0xFFFFu)) return 11;
  if ((got_bh & 0xFFFFu) != 0u) return 12;
  return 0;
}

static int rbm_run_once_irq(uint32_t expect_updates, uint32_t *cycles_out, uint32_t *updates_out) {
  uint32_t timeout;
  uint32_t status;
  uint32_t cycles;
  uint32_t updates;
  uint32_t stalls;
  uint32_t stats;
  uint32_t w00_before;
  uint32_t w00_after;
  uint32_t h0_0;

  rbm_irq_seen = 0;
  soc_irq_set_mask(0u);
  w00_before = rbm_mem_read(RBM_BASE, RBM_MEMSEL_W, mem_addr_2d(0u, 0u));

  rbm_wr(RBM_BASE, RBM_REG_CONTROL, RBM_CTRL_DETERM | RBM_CTRL_START);
  rbm_wr(RBM_BASE, RBM_REG_CONTROL, RBM_CTRL_DETERM);

  for (timeout = 0; timeout < 2000000u; ++timeout) {
    if (rbm_irq_seen != 0u) break;
    status = rbm_rd(RBM_BASE, RBM_REG_STATUS);
    if (status & RBM_STATUS_ERR) return 20;
  }

  if (timeout == 2000000u) return 21;

  rbm_wr(RBM_BASE, RBM_REG_INT_EN, 0u);
  status = rbm_rd(RBM_BASE, RBM_REG_STATUS);
  if ((status & RBM_STATUS_DONE) == 0u) return 22;

  cycles = rbm_rd(RBM_BASE, RBM_REG_PERF_CYCLES);
  updates = rbm_rd(RBM_BASE, RBM_REG_PERF_UPDATES);
  stalls = rbm_rd(RBM_BASE, RBM_REG_PERF_STALLS);
  stats = rbm_rd(RBM_BASE, RBM_REG_STATS);
  w00_after = rbm_mem_read(RBM_BASE, RBM_MEMSEL_W, mem_addr_2d(0u, 0u));
  h0_0 = rbm_mem_read(RBM_BASE, RBM_MEMSEL_H0_PROB, 0u);

  if (updates != expect_updates) return 23;
  if (cycles == 0u || stalls == 0u) return 24;
  if (w00_after == w00_before) return 25;

  *cycles_out = cycles;
  *updates_out = updates;
  return 0;
}

int main(void) {
  uint32_t cycles_run1 = 0;
  uint32_t cycles_run2 = 0;
  uint32_t updates_run1 = 0;
  uint32_t updates_run2 = 0;
  int rc;

  UART_DIV = 100;
  TIMER_CTRL = 0;

  uart_puts("rbm soc selftest\n");

  if (rbm_rd(RBM_BASE, RBM_REG_HW_VERSION) != RBM_HW_VERSION) {
    uart_puts("rbm version fail\n");
    return 1;
  }

  rbm_load_case(4u, 4u, 0x0100u);
  rc = rbm_self_check_load(4u, 4u, 0x0100u);
  if (rc != 0) return 100 + rc;

  rc = rbm_run_once_irq((4u * 4u) + 4u + 4u, &cycles_run1, &updates_run1);
  if (rc != 0) return 200 + rc;

  rbm_load_case(2u, 2u, 0x0200u);
  rc = rbm_self_check_load(2u, 2u, 0x0200u);
  if (rc != 0) return 300 + rc;

  rc = rbm_run_once_irq((2u * 2u) + 2u + 2u, &cycles_run2, &updates_run2);
  if (rc != 0) return 400 + rc;

  uart_put_label_dec("run1 cycles=", cycles_run1);
  uart_put_label_dec("run1 updates=", updates_run1);
  uart_put_label_dec("run2 cycles=", cycles_run2);
  uart_put_label_dec("run2 updates=", updates_run2);

  if (cycles_run2 >= cycles_run1) return 500;
  if (updates_run2 >= updates_run1) return 501;

  uart_puts("rbm selftest pass\n");
  return 0;
}
